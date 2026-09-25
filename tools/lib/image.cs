// Image engine of tools/image.ps1: PNG reading and writing, and the editing operations.
// Keep this file ASCII-only and within C# 5 (Windows PowerShell 5.1 compiles it with the .NET Framework compiler).
// Pixels are kept as straight (not premultiplied) RGBA, 8 bits per channel. Every image is written as an
// 8-bit RGBA PNG (color type 6). PNG files are read by the code below; other formats and the drawing
// operations use System.Drawing (GDI+).
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;

namespace GhostDevkit.Imaging
{
    public class ImageException : Exception
    {
        public ImageException(string message) : base(message) { }
    }

    public sealed class RgbaImage
    {
        public readonly int Width;
        public readonly int Height;
        public readonly byte[] Pixels;
        // How the image was stored in its file, for "info".
        public string Format = "new image";
        public bool HasAlphaChannel;
        public bool HasTrns;

        public RgbaImage(int width, int height)
        {
            if (width <= 0 || height <= 0) throw new ImageException("invalid image size " + width + "x" + height);
            if ((long)width * height > 64L * 1024 * 1024) throw new ImageException("image too large: " + width + "x" + height);
            Width = width;
            Height = height;
            Pixels = new byte[width * height * 4];
        }

        public RgbaImage Clone()
        {
            RgbaImage copy = new RgbaImage(Width, Height);
            Buffer.BlockCopy(Pixels, 0, copy.Pixels, 0, Pixels.Length);
            copy.Format = Format;
            copy.HasAlphaChannel = HasAlphaChannel;
            copy.HasTrns = HasTrns;
            return copy;
        }

        public bool Contains(int x, int y) { return x >= 0 && y >= 0 && x < Width && y < Height; }
    }

    public struct Rgba
    {
        public byte R, G, B, A;
        public Rgba(int r, int g, int b, int a) { R = (byte)r; G = (byte)g; B = (byte)b; A = (byte)a; }
        public static Rgba At(RgbaImage img, int x, int y)
        {
            int i = (y * img.Width + x) * 4;
            return new Rgba(img.Pixels[i], img.Pixels[i + 1], img.Pixels[i + 2], img.Pixels[i + 3]);
        }
        public override string ToString()
        {
            return "#" + R.ToString("x2") + G.ToString("x2") + B.ToString("x2") + A.ToString("x2");
        }
        public string ToRgbString()
        {
            return "#" + R.ToString("x2") + G.ToString("x2") + B.ToString("x2");
        }
    }

    public struct IntRect
    {
        public int X, Y, W, H;
        public IntRect(int x, int y, int w, int h) { X = x; Y = y; W = w; H = h; }
        public override string ToString() { return X + "," + Y + "," + W + "," + H; }
    }

    // ---------------------------------------------------------------- PNG

    public static class Png
    {
        static readonly byte[] Signature = { 137, 80, 78, 71, 13, 10, 26, 10 };
        static uint[] crcTable;

        public static bool IsPng(byte[] data)
        {
            if (data.Length < 8) return false;
            for (int i = 0; i < 8; i++) if (data[i] != Signature[i]) return false;
            return true;
        }

        static int ReadInt(byte[] d, int p)
        {
            return (d[p] << 24) | (d[p + 1] << 16) | (d[p + 2] << 8) | d[p + 3];
        }

        public static RgbaImage Decode(byte[] data)
        {
            if (!IsPng(data)) throw new ImageException("not a PNG file");
            int pos = 8, width = 0, height = 0, depth = 0, colorType = -1, interlace = 0;
            byte[] palette = null, trns = null;
            MemoryStream idat = new MemoryStream();
            bool ended = false;
            while (pos + 8 <= data.Length)
            {
                int length = ReadInt(data, pos);
                string type = Encoding.ASCII.GetString(data, pos + 4, 4);
                int start = pos + 8;
                if (length < 0 || start + length > data.Length) throw new ImageException("broken PNG (chunk " + type + " is truncated)");
                if (type == "IHDR")
                {
                    width = ReadInt(data, start);
                    height = ReadInt(data, start + 4);
                    depth = data[start + 8];
                    colorType = data[start + 9];
                    interlace = data[start + 12];
                }
                else if (type == "PLTE") { palette = new byte[length]; Buffer.BlockCopy(data, start, palette, 0, length); }
                else if (type == "tRNS") { trns = new byte[length]; Buffer.BlockCopy(data, start, trns, 0, length); }
                else if (type == "IDAT") { idat.Write(data, start, length); }
                else if (type == "IEND") { ended = true; break; }
                pos = start + length + 4;
            }
            if (colorType < 0) throw new ImageException("broken PNG (no IHDR)");
            if (!ended && idat.Length == 0) throw new ImageException("broken PNG (no image data)");
            int channels;
            switch (colorType)
            {
                case 0: channels = 1; break;
                case 2: channels = 3; break;
                case 3: channels = 1; break;
                case 4: channels = 2; break;
                case 6: channels = 4; break;
                default: throw new ImageException("unsupported PNG color type " + colorType);
            }
            bool depthOk = depth == 8 || depth == 16 || ((colorType == 0 || colorType == 3) && (depth == 1 || depth == 2 || depth == 4));
            if (!depthOk || (colorType == 3 && depth == 16)) throw new ImageException("unsupported PNG bit depth " + depth + " for color type " + colorType);
            if (colorType == 3 && palette == null) throw new ImageException("broken PNG (palette image without PLTE)");

            byte[] raw = Inflate(idat.ToArray());
            RgbaImage img = new RgbaImage(width, height);
            Decoder dec = new Decoder();
            dec.Raw = raw;
            dec.Img = img;
            dec.Depth = depth;
            dec.ColorType = colorType;
            dec.Channels = channels;
            dec.Palette = palette;
            dec.Trns = trns;
            if (interlace == 0)
            {
                dec.Pass(0, 0, 1, 1);
            }
            else
            {
                int[,] passes = { { 0, 0, 8, 8 }, { 4, 0, 8, 8 }, { 0, 4, 4, 8 }, { 2, 0, 4, 4 }, { 0, 2, 2, 4 }, { 1, 0, 2, 2 }, { 0, 1, 1, 2 } };
                for (int p = 0; p < 7; p++) dec.Pass(passes[p, 0], passes[p, 1], passes[p, 2], passes[p, 3]);
            }

            string[] names = { "grayscale", "?", "RGB", "palette", "grayscale+alpha", "?", "RGBA" };
            img.Format = "PNG " + depth + "-bit " + names[colorType] + (trns != null ? " with tRNS" : "") + (interlace != 0 ? ", interlaced" : "");
            img.HasAlphaChannel = colorType == 4 || colorType == 6;
            img.HasTrns = trns != null;
            return img;
        }

        sealed class Decoder
        {
            public byte[] Raw;
            public RgbaImage Img;
            public int Depth, ColorType, Channels;
            public byte[] Palette, Trns;
            int offset;

            int Sample(byte[] row, int index)
            {
                if (Depth == 8) return row[index];
                if (Depth == 16) return (row[index * 2] << 8) | row[index * 2 + 1];
                int bit = index * Depth;
                int shift = 8 - Depth - (bit & 7);
                return (row[bit >> 3] >> shift) & ((1 << Depth) - 1);
            }

            int To8(int v)
            {
                if (Depth == 16) return v >> 8;
                if (Depth == 8) return v;
                return v * 255 / ((1 << Depth) - 1);
            }

            int TrnsValue(int i) { return (Trns[i * 2] << 8) | Trns[i * 2 + 1]; }

            public void Pass(int sx, int sy, int dx, int dy)
            {
                int pw = (Img.Width - sx + dx - 1) / dx;
                int ph = (Img.Height - sy + dy - 1) / dy;
                if (pw <= 0 || ph <= 0) return;
                int bitsPerPixel = Channels * Depth;
                int bpp = Math.Max(1, bitsPerPixel / 8);
                int rowBytes = (pw * bitsPerPixel + 7) / 8;
                byte[] prev = new byte[rowBytes];
                byte[] cur = new byte[rowBytes];
                byte[] px = Img.Pixels;
                for (int y = 0; y < ph; y++)
                {
                    if (offset + 1 + rowBytes > Raw.Length) throw new ImageException("broken PNG (image data is too short)");
                    int filter = Raw[offset];
                    Buffer.BlockCopy(Raw, offset + 1, cur, 0, rowBytes);
                    offset += 1 + rowBytes;
                    Unfilter(filter, cur, prev, bpp);
                    int oy = sy + y * dy;
                    for (int x = 0; x < pw; x++)
                    {
                        int o = (oy * Img.Width + sx + x * dx) * 4;
                        int r, g, b, a = 255;
                        switch (ColorType)
                        {
                            case 0:
                                {
                                    int v = Sample(cur, x);
                                    r = g = b = To8(v);
                                    if (Trns != null && Trns.Length >= 2 && v == TrnsValue(0)) a = 0;
                                    break;
                                }
                            case 2:
                                {
                                    int vr = Sample(cur, x * 3), vg = Sample(cur, x * 3 + 1), vb = Sample(cur, x * 3 + 2);
                                    r = To8(vr); g = To8(vg); b = To8(vb);
                                    if (Trns != null && Trns.Length >= 6 && vr == TrnsValue(0) && vg == TrnsValue(1) && vb == TrnsValue(2)) a = 0;
                                    break;
                                }
                            case 3:
                                {
                                    int idx = Sample(cur, x);
                                    if (idx * 3 + 2 >= Palette.Length) throw new ImageException("broken PNG (palette index out of range)");
                                    r = Palette[idx * 3]; g = Palette[idx * 3 + 1]; b = Palette[idx * 3 + 2];
                                    if (Trns != null && idx < Trns.Length) a = Trns[idx];
                                    break;
                                }
                            case 4:
                                r = g = b = To8(Sample(cur, x * 2));
                                a = To8(Sample(cur, x * 2 + 1));
                                break;
                            default:
                                r = To8(Sample(cur, x * 4)); g = To8(Sample(cur, x * 4 + 1)); b = To8(Sample(cur, x * 4 + 2));
                                a = To8(Sample(cur, x * 4 + 3));
                                break;
                        }
                        px[o] = (byte)r; px[o + 1] = (byte)g; px[o + 2] = (byte)b; px[o + 3] = (byte)a;
                    }
                    byte[] t = prev; prev = cur; cur = t;
                }
            }
        }

        static void Unfilter(int filter, byte[] cur, byte[] prev, int bpp)
        {
            int n = cur.Length;
            switch (filter)
            {
                case 0: break;
                case 1: for (int i = bpp; i < n; i++) cur[i] = (byte)(cur[i] + cur[i - bpp]); break;
                case 2: for (int i = 0; i < n; i++) cur[i] = (byte)(cur[i] + prev[i]); break;
                case 3:
                    for (int i = 0; i < n; i++)
                    {
                        int left = i >= bpp ? cur[i - bpp] : 0;
                        cur[i] = (byte)(cur[i] + ((left + prev[i]) >> 1));
                    }
                    break;
                case 4:
                    for (int i = 0; i < n; i++)
                    {
                        int a = i >= bpp ? cur[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
                        cur[i] = (byte)(cur[i] + Paeth(a, b, c));
                    }
                    break;
                default: throw new ImageException("broken PNG (unknown filter " + filter + ")");
            }
        }

        static int Paeth(int a, int b, int c)
        {
            int p = a + b - c, pa = Math.Abs(p - a), pb = Math.Abs(p - b), pc = Math.Abs(p - c);
            if (pa <= pb && pa <= pc) return a;
            return pb <= pc ? b : c;
        }

        static byte[] Inflate(byte[] zlib)
        {
            if (zlib.Length < 2 || (zlib[0] & 0x0F) != 8) throw new ImageException("broken PNG (bad zlib header)");
            using (MemoryStream input = new MemoryStream(zlib, 2, zlib.Length - 2))
            using (DeflateStream inflater = new DeflateStream(input, CompressionMode.Decompress))
            using (MemoryStream output = new MemoryStream())
            {
                try { inflater.CopyTo(output); }
                catch (InvalidDataException) { throw new ImageException("broken PNG (bad compressed data)"); }
                return output.ToArray();
            }
        }

        public static byte[] Encode(RgbaImage img)
        {
            int stride = img.Width * 4;
            byte[] prev = new byte[stride], cur = new byte[stride];
            byte[][] candidates = new byte[5][];
            for (int f = 0; f < 5; f++) candidates[f] = new byte[stride];
            MemoryStream filtered = new MemoryStream();
            for (int y = 0; y < img.Height; y++)
            {
                Buffer.BlockCopy(img.Pixels, y * stride, cur, 0, stride);
                // Fully transparent pixels are written as 0,0,0,0: their color is never seen, and it compresses better.
                for (int i = 0; i < stride; i += 4) if (cur[i + 3] == 0) { cur[i] = 0; cur[i + 1] = 0; cur[i + 2] = 0; }
                int best = 0;
                long bestScore = long.MaxValue;
                for (int f = 0; f < 5; f++)
                {
                    byte[] c = candidates[f];
                    long score = 0;
                    for (int i = 0; i < stride; i++)
                    {
                        int a = i >= 4 ? cur[i - 4] : 0, b = prev[i], cc = i >= 4 ? prev[i - 4] : 0;
                        int predictor = f == 0 ? 0 : f == 1 ? a : f == 2 ? b : f == 3 ? (a + b) >> 1 : Paeth(a, b, cc);
                        byte v = (byte)(cur[i] - predictor);
                        c[i] = v;
                        score += v < 128 ? v : 256 - v;
                    }
                    if (score < bestScore) { bestScore = score; best = f; }
                }
                filtered.WriteByte((byte)best);
                filtered.Write(candidates[best], 0, stride);
                byte[] t = prev; prev = cur; cur = t;
            }
            byte[] rawData = filtered.ToArray();

            MemoryStream z = new MemoryStream();
            z.WriteByte(0x78); z.WriteByte(0xDA);
            using (DeflateStream deflater = new DeflateStream(z, CompressionLevel.Optimal, true))
            {
                deflater.Write(rawData, 0, rawData.Length);
            }
            uint adler = Adler32(rawData);
            z.WriteByte((byte)(adler >> 24)); z.WriteByte((byte)(adler >> 16)); z.WriteByte((byte)(adler >> 8)); z.WriteByte((byte)adler);

            MemoryStream png = new MemoryStream();
            png.Write(Signature, 0, 8);
            byte[] ihdr = new byte[13];
            WriteInt(ihdr, 0, img.Width);
            WriteInt(ihdr, 4, img.Height);
            ihdr[8] = 8;   // bit depth
            ihdr[9] = 6;   // color type: RGBA
            WriteChunk(png, "IHDR", ihdr);
            WriteChunk(png, "IDAT", z.ToArray());
            WriteChunk(png, "IEND", new byte[0]);
            return png.ToArray();
        }

        static void WriteInt(byte[] d, int p, int v)
        {
            d[p] = (byte)(v >> 24); d[p + 1] = (byte)(v >> 16); d[p + 2] = (byte)(v >> 8); d[p + 3] = (byte)v;
        }

        static void WriteChunk(Stream s, string type, byte[] body)
        {
            byte[] head = new byte[8];
            WriteInt(head, 0, body.Length);
            Encoding.ASCII.GetBytes(type, 0, 4, head, 4);
            s.Write(head, 0, 8);
            s.Write(body, 0, body.Length);
            uint crc = Crc(head, 4, 4, 0xFFFFFFFF);
            crc = Crc(body, 0, body.Length, crc) ^ 0xFFFFFFFF;
            byte[] tail = new byte[4];
            WriteInt(tail, 0, (int)crc);
            s.Write(tail, 0, 4);
        }

        static uint Crc(byte[] d, int start, int count, uint crc)
        {
            if (crcTable == null)
            {
                uint[] table = new uint[256];
                for (uint n = 0; n < 256; n++)
                {
                    uint c = n;
                    for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
                    table[n] = c;
                }
                crcTable = table;
            }
            for (int i = start; i < start + count; i++) crc = crcTable[(crc ^ d[i]) & 0xFF] ^ (crc >> 8);
            return crc;
        }

        static uint Adler32(byte[] d)
        {
            uint a = 1, b = 0;
            int i = 0;
            while (i < d.Length)
            {
                int end = Math.Min(d.Length, i + 5552);
                for (; i < end; i++) { a += d[i]; b += a; }
                a %= 65521; b %= 65521;
            }
            return (b << 16) | a;
        }
    }

    // ---------------------------------------------------------------- loading, saving, GDI+

    public static class ImageIO
    {
        public static RgbaImage Load(string path)
        {
            if (!File.Exists(path)) throw new ImageException("file not found: " + path);
            byte[] data = File.ReadAllBytes(path);
            if (Png.IsPng(data)) return Png.Decode(data);
            RgbaImage img;
            try
            {
                using (MemoryStream ms = new MemoryStream(data))
                using (Bitmap bmp = new Bitmap(ms))
                {
                    img = Gdi.FromBitmap(bmp);
                    img.Format = new ImageFormatConverter().ConvertToString(bmp.RawFormat).ToUpperInvariant() + " " + bmp.PixelFormat;
                    img.HasAlphaChannel = (bmp.PixelFormat & System.Drawing.Imaging.PixelFormat.Alpha) != 0;
                }
            }
            catch (ImageException) { throw; }
            catch (Exception e) { throw new ImageException("cannot read " + path + ": " + e.Message); }
            return img;
        }

        public static void Save(RgbaImage img, string path)
        {
            if (!string.Equals(Path.GetExtension(path), ".png", StringComparison.OrdinalIgnoreCase))
                throw new ImageException("the output must be a .png file: " + path);
            string dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            byte[] data = Png.Encode(img);
            string temp = path + ".tmp-" + Guid.NewGuid().ToString("N");
            File.WriteAllBytes(temp, data);
            if (File.Exists(path)) File.Delete(path);
            File.Move(temp, path);
        }

        public static string Resolve(string baseDir, string path)
        {
            if (string.IsNullOrEmpty(path)) throw new ImageException("empty file name");
            return Path.GetFullPath(Path.IsPathRooted(path) ? path : Path.Combine(baseDir, path));
        }
    }

    public static class Gdi
    {
        public static RgbaImage FromBitmap(Bitmap bmp)
        {
            RgbaImage img = new RgbaImage(bmp.Width, bmp.Height);
            BitmapData bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            try
            {
                byte[] row = new byte[bmp.Width * 4];
                for (int y = 0; y < bmp.Height; y++)
                {
                    Marshal.Copy(new IntPtr(bd.Scan0.ToInt64() + (long)y * bd.Stride), row, 0, row.Length);
                    int o = y * bmp.Width * 4;
                    for (int x = 0; x < row.Length; x += 4)
                    {
                        img.Pixels[o + x] = row[x + 2];
                        img.Pixels[o + x + 1] = row[x + 1];
                        img.Pixels[o + x + 2] = row[x];
                        img.Pixels[o + x + 3] = row[x + 3];
                    }
                }
            }
            finally { bmp.UnlockBits(bd); }
            return img;
        }

        // Renders shapes or text in white on a transparent bitmap and returns the coverage (0..1) of each pixel.
        // Pixel (x, y) covers the square from (x, y) to (x + 1, y + 1).
        public static float[] Coverage(int width, int height, bool antialias, Action<Graphics> draw)
        {
            using (Bitmap bmp = new Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.Clear(Color.Transparent);
                    g.SmoothingMode = antialias ? SmoothingMode.AntiAlias : SmoothingMode.None;
                    g.PixelOffsetMode = PixelOffsetMode.Half;
                    g.TextRenderingHint = antialias ? TextRenderingHint.AntiAliasGridFit : TextRenderingHint.SingleBitPerPixelGridFit;
                    draw(g);
                }
                RgbaImage img = FromBitmap(bmp);
                float[] cov = new float[width * height];
                for (int i = 0; i < cov.Length; i++) cov[i] = img.Pixels[i * 4 + 3] / 255f;
                return cov;
            }
        }

        public static FontFamily Family(string name)
        {
            if (string.IsNullOrEmpty(name))
            {
                foreach (string candidate in new string[] { "Meiryo", "Yu Gothic UI", "MS UI Gothic" })
                {
                    try { return new FontFamily(candidate); } catch (ArgumentException) { }
                }
                return FontFamily.GenericSansSerif;
            }
            try { return new FontFamily(name); }
            catch (ArgumentException) { throw new ImageException("font not found: " + name); }
        }
    }

    // ---------------------------------------------------------------- argument parsing

    public sealed class OpArgs
    {
        public readonly string Name;
        readonly List<string> positional = new List<string>();
        readonly List<bool> positionalUsed = new List<bool>();
        readonly Dictionary<string, string> named = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        readonly HashSet<string> namedUsed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        public readonly string Text;

        public OpArgs(string text)
        {
            Text = text;
            List<KeyValuePair<string, bool>> tokens = Tokenize(text);
            if (tokens.Count == 0) throw new ImageException("empty operation");
            Name = tokens[0].Key.ToLowerInvariant();
            for (int i = 1; i < tokens.Count; i++)
            {
                string t = tokens[i].Key;
                int eq = t.IndexOf('=');
                if (!tokens[i].Value && eq > 0 && IsIdentifier(t.Substring(0, eq)))
                {
                    named[t.Substring(0, eq)] = t.Substring(eq + 1);
                }
                else
                {
                    positional.Add(t);
                    positionalUsed.Add(false);
                }
            }
        }

        static bool IsIdentifier(string s)
        {
            foreach (char c in s) if (!(char.IsLetter(c) && c < 128)) return false;
            return s.Length > 0;
        }

        // Splits on white space; '...' and "..." keep spaces (a doubled quote inside stands for the quote itself).
        static List<KeyValuePair<string, bool>> Tokenize(string s)
        {
            List<KeyValuePair<string, bool>> result = new List<KeyValuePair<string, bool>>();
            int i = 0;
            while (i < s.Length)
            {
                while (i < s.Length && char.IsWhiteSpace(s[i])) i++;
                if (i >= s.Length) break;
                StringBuilder sb = new StringBuilder();
                bool quoted = false;
                while (i < s.Length && !char.IsWhiteSpace(s[i]))
                {
                    char c = s[i];
                    if (c == '\'' || c == '"')
                    {
                        quoted = true;
                        i++;
                        while (true)
                        {
                            if (i >= s.Length) throw new ImageException("unclosed quote in: " + s);
                            if (s[i] == c)
                            {
                                if (i + 1 < s.Length && s[i + 1] == c) { sb.Append(c); i += 2; continue; }
                                i++;
                                break;
                            }
                            sb.Append(s[i++]);
                        }
                    }
                    else { sb.Append(c); i++; }
                }
                result.Add(new KeyValuePair<string, bool>(sb.ToString(), quoted));
            }
            return result;
        }

        public int PositionalCount { get { return positional.Count; } }

        public string Pos(int index, string what)
        {
            if (index >= positional.Count) throw new ImageException(Name + ": missing " + what);
            positionalUsed[index] = true;
            return positional[index];
        }

        public string PosOr(int index, string fallback)
        {
            if (index >= positional.Count) return fallback;
            positionalUsed[index] = true;
            return positional[index];
        }

        public string Get(string key, string fallback)
        {
            string v;
            if (named.TryGetValue(key, out v)) { namedUsed.Add(key); return v; }
            return fallback;
        }

        public bool Has(string key) { return named.ContainsKey(key); }

        // Takes a bare word such as "bold" from the positional arguments.
        public bool Flag(string word)
        {
            for (int i = 0; i < positional.Count; i++)
            {
                if (!positionalUsed[i] && string.Equals(positional[i], word, StringComparison.OrdinalIgnoreCase)) { positionalUsed[i] = true; return true; }
            }
            return false;
        }

        public void Done()
        {
            for (int i = 0; i < positional.Count; i++)
                if (!positionalUsed[i]) throw new ImageException(Name + ": unexpected argument '" + positional[i] + "'");
            foreach (string key in named.Keys)
                if (!namedUsed.Contains(key)) throw new ImageException(Name + ": unknown option '" + key + "='");
        }
    }

    public static class Parse
    {
        static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

        public static double Number(string s, string what)
        {
            double v;
            if (!double.TryParse(s, NumberStyles.Float, Inv, out v)) throw new ImageException("bad " + what + ": '" + s + "'");
            return v;
        }

        public static int Int(string s, string what)
        {
            int v;
            if (!int.TryParse(s, NumberStyles.Integer, Inv, out v)) throw new ImageException("bad " + what + ": '" + s + "' (an integer is expected)");
            return v;
        }

        // "0.5" or "50%" -> 0.5
        public static double Fraction(string s, string what)
        {
            s = s.Trim();
            if (s.EndsWith("%")) return Number(s.Substring(0, s.Length - 1), what) / 100.0;
            return Number(s, what);
        }

        public static int[] Ints(string s, int count, string what)
        {
            string[] parts = s.Split(',');
            if (parts.Length != count) throw new ImageException("bad " + what + ": '" + s + "' (" + count + " comma-separated integers are expected)");
            int[] r = new int[count];
            for (int i = 0; i < count; i++) r[i] = Int(parts[i].Trim(), what);
            return r;
        }

        public static double[] Numbers(string s, string what)
        {
            string[] parts = s.Split(',');
            double[] r = new double[parts.Length];
            for (int i = 0; i < parts.Length; i++) r[i] = Number(parts[i].Trim(), what);
            return r;
        }

        public static IntRect Rect(string s)
        {
            int[] v = Ints(s, 4, "rectangle x,y,w,h");
            if (v[2] <= 0 || v[3] <= 0) throw new ImageException("bad rectangle '" + s + "' (width and height must be positive)");
            return new IntRect(v[0], v[1], v[2], v[3]);
        }

        // "WxH"; with allowAuto, "Wx" or "xH" (or 0) leaves one side to keep the aspect ratio (returned as 0).
        public static int[] Size(string s, bool allowAuto)
        {
            int x = s.IndexOfAny(new char[] { 'x', 'X' });
            if (x < 0) throw new ImageException("bad size '" + s + "' (WxH is expected)");
            string ws = s.Substring(0, x).Trim(), hs = s.Substring(x + 1).Trim();
            int w = ws.Length == 0 && allowAuto ? 0 : Int(ws, "width");
            int h = hs.Length == 0 && allowAuto ? 0 : Int(hs, "height");
            if (w < 0 || h < 0 || (!allowAuto && (w == 0 || h == 0)) || (w == 0 && h == 0)) throw new ImageException("bad size '" + s + "'");
            return new int[] { w, h };
        }

        public static Rgba Color(string s)
        {
            string t = s.Trim().ToLowerInvariant();
            if (t == "transparent" || t == "none") return new Rgba(0, 0, 0, 0);
            if (t == "black") return new Rgba(0, 0, 0, 255);
            if (t == "white") return new Rgba(255, 255, 255, 255);
            if (t.StartsWith("#")) t = t.Substring(1);
            else throw new ImageException("bad color '" + s + "' (use #rgb, #rrggbb, #rrggbbaa, black, white or transparent)");
            if (t.Length == 3 || t.Length == 4)
            {
                StringBuilder sb = new StringBuilder();
                foreach (char c in t) { sb.Append(c); sb.Append(c); }
                t = sb.ToString();
            }
            if (t.Length != 6 && t.Length != 8) throw new ImageException("bad color '" + s + "'");
            int[] v = new int[4];
            v[3] = 255;
            for (int i = 0; i < t.Length / 2; i++)
            {
                int b;
                if (!int.TryParse(t.Substring(i * 2, 2), NumberStyles.HexNumber, Inv, out b)) throw new ImageException("bad color '" + s + "'");
                v[i] = b;
            }
            return new Rgba(v[0], v[1], v[2], v[3]);
        }
    }

    // ---------------------------------------------------------------- pixel helpers

    public static class Px
    {
        public static int Clamp255(double v) { return v <= 0 ? 0 : v >= 255 ? 255 : (int)(v + 0.5); }
        public static double Clamp01(double v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

        // Premultiplied float copy (r, g, b, a in 0..1).
        public static float[] Premultiply(RgbaImage img)
        {
            float[] f = new float[img.Pixels.Length];
            byte[] p = img.Pixels;
            for (int i = 0; i < p.Length; i += 4)
            {
                float a = p[i + 3] / 255f;
                f[i] = p[i] / 255f * a; f[i + 1] = p[i + 1] / 255f * a; f[i + 2] = p[i + 2] / 255f * a; f[i + 3] = a;
            }
            return f;
        }

        public static RgbaImage Unpremultiply(float[] f, int w, int h)
        {
            RgbaImage img = new RgbaImage(w, h);
            byte[] p = img.Pixels;
            for (int i = 0; i < p.Length; i += 4)
            {
                float a = f[i + 3];
                if (a <= 0.5f / 255f) continue;
                if (a > 1) a = 1;
                p[i] = (byte)Clamp255(f[i] / a * 255); p[i + 1] = (byte)Clamp255(f[i + 1] / a * 255); p[i + 2] = (byte)Clamp255(f[i + 2] / a * 255);
                p[i + 3] = (byte)Clamp255(a * 255);
            }
            return img;
        }

        // Porter-Duff "source over destination" with straight alpha; sa is the effective source alpha (0..1).
        public static void Over(byte[] d, int di, int sr, int sg, int sb, double sa)
        {
            if (sa <= 0) return;
            double da = d[di + 3] / 255.0;
            double oa = sa + da * (1 - sa);
            if (oa <= 0) { d[di] = d[di + 1] = d[di + 2] = d[di + 3] = 0; return; }
            double k = da * (1 - sa);
            d[di] = (byte)Clamp255((sr * sa + d[di] * k) / oa);
            d[di + 1] = (byte)Clamp255((sg * sa + d[di + 1] * k) / oa);
            d[di + 2] = (byte)Clamp255((sb * sa + d[di + 2] * k) / oa);
            d[di + 3] = (byte)Clamp255(oa * 255);
        }

        // Moves pixel d toward (r, g, b, a) by t (0..1), in premultiplied space so that transparent colors do not leak.
        public static void Lerp(byte[] d, int di, int r, int g, int b, int a, double t)
        {
            if (t <= 0) return;
            if (t >= 1) { d[di] = (byte)r; d[di + 1] = (byte)g; d[di + 2] = (byte)b; d[di + 3] = (byte)a; return; }
            double da = d[di + 3] / 255.0, sa = a / 255.0;
            double oa = da + (sa - da) * t;
            if (oa <= 0) { d[di] = d[di + 1] = d[di + 2] = d[di + 3] = 0; return; }
            d[di] = (byte)Clamp255((d[di] * da + (r * sa - d[di] * da) * t) / oa);
            d[di + 1] = (byte)Clamp255((d[di + 1] * da + (g * sa - d[di + 1] * da) * t) / oa);
            d[di + 2] = (byte)Clamp255((d[di + 2] * da + (b * sa - d[di + 2] * da) * t) / oa);
            d[di + 3] = (byte)Clamp255(oa * 255);
        }

        public static double Luma(int r, int g, int b) { return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0; }

        public static void ToHsl(double r, double g, double b, out double h, out double s, out double l)
        {
            double max = Math.Max(r, Math.Max(g, b)), min = Math.Min(r, Math.Min(g, b));
            l = (max + min) / 2;
            if (max == min) { h = 0; s = 0; return; }
            double d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            if (max == r) h = (g - b) / d + (g < b ? 6 : 0);
            else if (max == g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h /= 6;
        }

        public static void FromHsl(double h, double s, double l, out double r, out double g, out double b)
        {
            if (s <= 0) { r = g = b = l; return; }
            double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
            double p = 2 * l - q;
            r = Hue(p, q, h + 1.0 / 3); g = Hue(p, q, h); b = Hue(p, q, h - 1.0 / 3);
        }

        static double Hue(double p, double q, double t)
        {
            if (t < 0) t += 1;
            if (t > 1) t -= 1;
            if (t < 1.0 / 6) return p + (q - p) * 6 * t;
            if (t < 0.5) return q;
            if (t < 2.0 / 3) return p + (q - p) * (2.0 / 3 - t) * 6;
            return p;
        }

        public static bool Similar(byte[] p, int i, Rgba c, int tolerance, bool compareAlpha)
        {
            if (compareAlpha)
            {
                if (p[i + 3] == 0 && c.A == 0) return true;
                if (Math.Abs(p[i + 3] - c.A) > tolerance) return false;
            }
            return Math.Abs(p[i] - c.R) <= tolerance && Math.Abs(p[i + 1] - c.G) <= tolerance && Math.Abs(p[i + 2] - c.B) <= tolerance;
        }

        // Gaussian blur of premultiplied data; pixels outside the image count as transparent.
        public static float[] Blur(float[] src, int w, int h, double sigma)
        {
            if (sigma <= 0) return (float[])src.Clone();
            int radius = (int)Math.Ceiling(sigma * 3);
            float[] kernel = new float[radius * 2 + 1];
            double sum = 0;
            for (int i = -radius; i <= radius; i++) { kernel[i + radius] = (float)Math.Exp(-(i * i) / (2 * sigma * sigma)); sum += kernel[i + radius]; }
            for (int i = 0; i < kernel.Length; i++) kernel[i] = (float)(kernel[i] / sum);
            float[] tmp = new float[src.Length], dst = new float[src.Length];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    float r = 0, g = 0, b = 0, a = 0;
                    for (int k = -radius; k <= radius; k++)
                    {
                        int sx = x + k;
                        if (sx < 0 || sx >= w) continue;
                        int si = (y * w + sx) * 4;
                        float kv = kernel[k + radius];
                        r += src[si] * kv; g += src[si + 1] * kv; b += src[si + 2] * kv; a += src[si + 3] * kv;
                    }
                    int o = (y * w + x) * 4;
                    tmp[o] = r; tmp[o + 1] = g; tmp[o + 2] = b; tmp[o + 3] = a;
                }
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    float r = 0, g = 0, b = 0, a = 0;
                    for (int k = -radius; k <= radius; k++)
                    {
                        int sy = y + k;
                        if (sy < 0 || sy >= h) continue;
                        int si = (sy * w + x) * 4;
                        float kv = kernel[k + radius];
                        r += tmp[si] * kv; g += tmp[si + 1] * kv; b += tmp[si + 2] * kv; a += tmp[si + 3] * kv;
                    }
                    int o = (y * w + x) * 4;
                    dst[o] = r; dst[o + 1] = g; dst[o + 2] = b; dst[o + 3] = a;
                }
            return dst;
        }

        // Bounding box of the pixels whose alpha is above the threshold, or null when there are none.
        public static IntRect? Bounds(RgbaImage img, int threshold)
        {
            int minX = int.MaxValue, minY = int.MaxValue, maxX = -1, maxY = -1;
            for (int y = 0; y < img.Height; y++)
                for (int x = 0; x < img.Width; x++)
                    if (img.Pixels[(y * img.Width + x) * 4 + 3] > threshold)
                    {
                        if (x < minX) minX = x;
                        if (x > maxX) maxX = x;
                        if (y < minY) minY = y;
                        if (y > maxY) maxY = y;
                    }
            if (maxX < 0) return null;
            return new IntRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
        }

        public static RgbaImage Crop(RgbaImage img, int x0, int y0, int w, int h, Rgba fill)
        {
            RgbaImage r = new RgbaImage(w, h);
            byte[] d = r.Pixels, s = img.Pixels;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int sx = x + x0, sy = y + y0, di = (y * w + x) * 4;
                    if (img.Contains(sx, sy))
                    {
                        Buffer.BlockCopy(s, (sy * img.Width + sx) * 4, d, di, 4);
                    }
                    else
                    {
                        d[di] = fill.R; d[di + 1] = fill.G; d[di + 2] = fill.B; d[di + 3] = fill.A;
                    }
                }
            return r;
        }
    }

    // ---------------------------------------------------------------- resampling

    public static class Resample
    {
        static double Sinc(double x) { if (x == 0) return 1; x *= Math.PI; return Math.Sin(x) / x; }

        static double Kernel(string filter, double x)
        {
            x = Math.Abs(x);
            switch (filter)
            {
                case "box": return x <= 0.5 ? 1 : 0;
                case "bilinear": return x < 1 ? 1 - x : 0;
                case "bicubic":
                    // Catmull-Rom
                    if (x < 1) return 1.5 * x * x * x - 2.5 * x * x + 1;
                    if (x < 2) return -0.5 * x * x * x + 2.5 * x * x - 4 * x + 2;
                    return 0;
                default:
                    return x < 3 ? Sinc(x) * Sinc(x / 3) : 0;
            }
        }

        static double Support(string filter)
        {
            switch (filter) { case "box": return 0.5; case "bilinear": return 1; case "bicubic": return 2; default: return 3; }
        }

        public static string CheckFilter(string filter)
        {
            string f = filter.ToLowerInvariant();
            if (f != "nearest" && f != "box" && f != "bilinear" && f != "bicubic" && f != "lanczos")
                throw new ImageException("unknown filter '" + filter + "' (nearest, box, bilinear, bicubic, lanczos)");
            return f;
        }

        public static RgbaImage Resize(RgbaImage img, int w, int h, string filter)
        {
            if (filter == "nearest")
            {
                RgbaImage r = new RgbaImage(w, h);
                for (int y = 0; y < h; y++)
                {
                    int sy = Math.Min(img.Height - 1, (int)((y + 0.5) * img.Height / h));
                    for (int x = 0; x < w; x++)
                    {
                        int sx = Math.Min(img.Width - 1, (int)((x + 0.5) * img.Width / w));
                        Buffer.BlockCopy(img.Pixels, (sy * img.Width + sx) * 4, r.Pixels, (y * w + x) * 4, 4);
                    }
                }
                return r;
            }
            float[] src = Px.Premultiply(img);
            float[] tmp = Pass(src, img.Width, img.Height, w, true, filter);
            float[] dst = Pass(tmp, w, img.Height, h, false, filter);
            return Px.Unpremultiply(dst, w, h);
        }

        // Resamples one axis: horizontal (w -> newSize) or vertical (h -> newSize).
        static float[] Pass(float[] src, int w, int h, int newSize, bool horizontal, string filter)
        {
            int srcSize = horizontal ? w : h;
            int ow = horizontal ? newSize : w, oh = horizontal ? h : newSize;
            float[] dst = new float[ow * oh * 4];
            double scale = (double)srcSize / newSize;
            double fscale = Math.Max(1, scale);
            double support = Support(filter) * fscale;
            for (int i = 0; i < newSize; i++)
            {
                double center = (i + 0.5) * scale - 0.5;
                int left = (int)Math.Ceiling(center - support), right = (int)Math.Floor(center + support);
                List<int> idx = new List<int>();
                List<double> wts = new List<double>();
                double total = 0;
                for (int j = left; j <= right; j++)
                {
                    double wv = Kernel(filter, (j - center) / fscale);
                    if (wv == 0) continue;
                    idx.Add(Math.Min(srcSize - 1, Math.Max(0, j)));
                    wts.Add(wv);
                    total += wv;
                }
                if (idx.Count == 0) { idx.Add(Math.Min(srcSize - 1, Math.Max(0, (int)Math.Round(center)))); wts.Add(1); total = 1; }
                int lines = horizontal ? h : w;
                for (int line = 0; line < lines; line++)
                {
                    double r = 0, g = 0, b = 0, a = 0;
                    for (int k = 0; k < idx.Count; k++)
                    {
                        int si = horizontal ? (line * w + idx[k]) * 4 : (idx[k] * w + line) * 4;
                        double wv = wts[k] / total;
                        r += src[si] * wv; g += src[si + 1] * wv; b += src[si + 2] * wv; a += src[si + 3] * wv;
                    }
                    int di = horizontal ? (line * ow + i) * 4 : (i * ow + line) * 4;
                    // Sharp filters overshoot; keep the premultiplied color within the alpha.
                    float fa = (float)Math.Max(0, Math.Min(1, a));
                    dst[di] = (float)Math.Max(0, Math.Min(fa, r));
                    dst[di + 1] = (float)Math.Max(0, Math.Min(fa, g));
                    dst[di + 2] = (float)Math.Max(0, Math.Min(fa, b));
                    dst[di + 3] = fa;
                }
            }
            return dst;
        }
    }

    // ---------------------------------------------------------------- operations

    public sealed class Editor
    {
        public RgbaImage Image;
        public readonly List<string> Log = new List<string>();
        readonly string baseDir;
        readonly string inputPath;

        public Editor(RgbaImage image, string baseDir, string inputPath)
        {
            Image = image;
            this.baseDir = baseDir;
            this.inputPath = inputPath;
        }

        RgbaImage LoadFile(string name) { return ImageIO.Load(ImageIO.Resolve(baseDir, name)); }

        public void Apply(string text)
        {
            OpArgs a = new OpArgs(text);
            switch (a.Name)
            {
                case "crop": Crop(a); break;
                case "trim": Trim(a); break;
                case "canvas": Canvas(a); break;
                case "pad": Pad(a); break;
                case "offset": Offset(a); break;
                case "resize": ResizeOp(a); break;
                case "scale": Scale(a); break;
                case "flip": Flip(a); break;
                case "rotate": Rotate(a); break;
                case "paste": Paste(a); break;
                case "colorkey": ColorKey(a); break;
                case "pna": Pna(a); break;
                case "mask": Mask(a); break;
                case "opacity": Opacity(a); break;
                case "threshold": Threshold(a); break;
                case "flatten": Flatten(a); break;
                case "fill": Fill(a, false); break;
                case "clear": Fill(a, true); break;
                case "floodfill": FloodFill(a); break;
                case "replace": Replace(a); break;
                case "adjust": Adjust(a); break;
                case "colorize": Colorize(a); break;
                case "grayscale": PixelMap(a, delegate (ref double r, ref double g, ref double b) { double l = 0.299 * r + 0.587 * g + 0.114 * b; r = g = b = l; }); break;
                case "invert": PixelMap(a, delegate (ref double r, ref double g, ref double b) { r = 1 - r; g = 1 - g; b = 1 - b; }); break;
                case "blur": BlurOp(a); break;
                case "sharpen": Sharpen(a); break;
                case "outline": Outline(a); break;
                case "shadow": Shadow(a); break;
                case "rect": Draw(a, "rect"); break;
                case "ellipse": Draw(a, "ellipse"); break;
                case "line": Draw(a, "line"); break;
                case "polygon": Draw(a, "polygon"); break;
                case "text": Draw(a, "text"); break;
                default: throw new ImageException("unknown operation '" + a.Name + "'");
            }
            a.Done();
        }

        // ---- geometry

        void Crop(OpArgs a)
        {
            IntRect r = Parse.Rect(a.Pos(0, "rectangle x,y,w,h"));
            Image = Px.Crop(Image, r.X, r.Y, r.W, r.H, new Rgba(0, 0, 0, 0));
        }

        void Trim(OpArgs a)
        {
            int pad = Parse.Int(a.Get("pad", "0"), "pad");
            int threshold = Parse.Int(a.Get("alpha", "0"), "alpha");
            IntRect? found = Px.Bounds(Image, threshold);
            if (found == null) throw new ImageException("trim: the image has no visible pixel");
            IntRect r = found.Value;
            r = new IntRect(r.X - pad, r.Y - pad, r.W + pad * 2, r.H + pad * 2);
            Image = Px.Crop(Image, r.X, r.Y, r.W, r.H, new Rgba(0, 0, 0, 0));
            Log.Add("trim: kept " + r + " (x,y,w,h) of the previous image; its top-left is now at 0,0");
        }

        void Canvas(OpArgs a)
        {
            int[] size = Parse.Size(a.Pos(0, "size WxH"), false);
            Rgba fill = Parse.Color(a.Get("color", "transparent"));
            string at = a.PosOr(1, "0,0");
            int x, y;
            if (at.Equals("center", StringComparison.OrdinalIgnoreCase)) { x = (size[0] - Image.Width) / 2; y = (size[1] - Image.Height) / 2; }
            else { int[] p = Parse.Ints(at, 2, "position x,y"); x = p[0]; y = p[1]; }
            Image = Place(Image, size[0], size[1], x, y, fill);
            Log.Add("canvas: the previous image is at " + x + "," + y);
        }

        static RgbaImage Place(RgbaImage img, int w, int h, int x, int y, Rgba fill)
        {
            return Px.Crop(img, -x, -y, w, h, fill);
        }

        void Pad(OpArgs a)
        {
            string s = a.Pos(0, "padding N or left,top,right,bottom");
            int[] p = s.Contains(",") ? Parse.Ints(s, 4, "padding left,top,right,bottom") : new int[] { Parse.Int(s, "padding"), 0, 0, 0 };
            if (!s.Contains(",")) { p[1] = p[2] = p[3] = p[0]; }
            Rgba fill = Parse.Color(a.Get("color", "transparent"));
            int w = Image.Width + p[0] + p[2], h = Image.Height + p[1] + p[3];
            Image = Place(Image, w, h, p[0], p[1], fill);
        }

        void Offset(OpArgs a)
        {
            int[] d = Parse.Ints(a.Pos(0, "offset dx,dy"), 2, "offset dx,dy");
            Image = Place(Image, Image.Width, Image.Height, d[0], d[1], new Rgba(0, 0, 0, 0));
        }

        void ResizeOp(OpArgs a)
        {
            int[] size = Parse.Size(a.Pos(0, "size WxH"), true);
            int w = size[0], h = size[1];
            if (w == 0) w = Math.Max(1, (int)Math.Round((double)Image.Width * h / Image.Height));
            if (h == 0) h = Math.Max(1, (int)Math.Round((double)Image.Height * w / Image.Width));
            Image = Resample.Resize(Image, w, h, Resample.CheckFilter(a.Get("filter", "bicubic")));
        }

        void Scale(OpArgs a)
        {
            double f = Parse.Fraction(a.Pos(0, "factor"), "factor");
            if (f <= 0) throw new ImageException("scale: the factor must be positive");
            int w = Math.Max(1, (int)Math.Round(Image.Width * f)), h = Math.Max(1, (int)Math.Round(Image.Height * f));
            Image = Resample.Resize(Image, w, h, Resample.CheckFilter(a.Get("filter", "bicubic")));
        }

        void Flip(OpArgs a)
        {
            string dir = a.Pos(0, "direction h or v").ToLowerInvariant();
            if (dir != "h" && dir != "v") throw new ImageException("flip: use h (left-right) or v (top-bottom)");
            RgbaImage r = new RgbaImage(Image.Width, Image.Height);
            for (int y = 0; y < Image.Height; y++)
                for (int x = 0; x < Image.Width; x++)
                {
                    int sx = dir == "h" ? Image.Width - 1 - x : x, sy = dir == "v" ? Image.Height - 1 - y : y;
                    Buffer.BlockCopy(Image.Pixels, (sy * Image.Width + sx) * 4, r.Pixels, (y * Image.Width + x) * 4, 4);
                }
            Image = r;
        }

        void Rotate(OpArgs a)
        {
            double deg = Parse.Number(a.Pos(0, "angle"), "angle");
            bool expand = a.Get("expand", "1") != "0";
            double norm = ((deg % 360) + 360) % 360;
            RgbaImage src = Image;
            int w = src.Width, h = src.Height;
            if (norm == 0) return;
            if (norm == 90 || norm == 180 || norm == 270)
            {
                int nw = norm == 180 ? w : h, nh = norm == 180 ? h : w;
                RgbaImage r = new RgbaImage(nw, nh);
                for (int y = 0; y < nh; y++)
                    for (int x = 0; x < nw; x++)
                    {
                        int sx, sy;
                        if (norm == 90) { sx = y; sy = h - 1 - x; }
                        else if (norm == 180) { sx = w - 1 - x; sy = h - 1 - y; }
                        else { sx = w - 1 - y; sy = x; }
                        Buffer.BlockCopy(src.Pixels, (sy * w + sx) * 4, r.Pixels, (y * nw + x) * 4, 4);
                    }
                if (!expand && (nw != w || nh != h)) r = Place(r, w, h, (w - nw) / 2, (h - nh) / 2, new Rgba(0, 0, 0, 0));
                Image = r;
                return;
            }
            // Clockwise on the screen (y points down). Bilinear, in premultiplied space.
            double rad = norm * Math.PI / 180, cos = Math.Cos(rad), sin = Math.Sin(rad);
            int ow = w, oh = h;
            if (expand)
            {
                ow = (int)Math.Ceiling(Math.Abs(w * cos) + Math.Abs(h * sin) - 1e-9);
                oh = (int)Math.Ceiling(Math.Abs(w * sin) + Math.Abs(h * cos) - 1e-9);
            }
            float[] s = Px.Premultiply(src);
            float[] d = new float[ow * oh * 4];
            double cx = w / 2.0, cy = h / 2.0, ocx = ow / 2.0, ocy = oh / 2.0;
            for (int y = 0; y < oh; y++)
                for (int x = 0; x < ow; x++)
                {
                    double dx = x + 0.5 - ocx, dy = y + 0.5 - ocy;
                    double sx = cos * dx + sin * dy + cx - 0.5, sy = -sin * dx + cos * dy + cy - 0.5;
                    int x0 = (int)Math.Floor(sx), y0 = (int)Math.Floor(sy);
                    double fx = sx - x0, fy = sy - y0;
                    int o = (y * ow + x) * 4;
                    for (int j = 0; j < 2; j++)
                        for (int i = 0; i < 2; i++)
                        {
                            int px = x0 + i, py = y0 + j;
                            if (px < 0 || py < 0 || px >= w || py >= h) continue;
                            double wv = (i == 0 ? 1 - fx : fx) * (j == 0 ? 1 - fy : fy);
                            int si = (py * w + px) * 4;
                            d[o] += (float)(s[si] * wv); d[o + 1] += (float)(s[si + 1] * wv); d[o + 2] += (float)(s[si + 2] * wv); d[o + 3] += (float)(s[si + 3] * wv);
                        }
                }
            Image = Px.Unpremultiply(d, ow, oh);
            if (expand) Log.Add("rotate: the new image is " + ow + "x" + oh + "; the old center is at its center");
        }

        // ---- compositing

        void Paste(OpArgs a)
        {
            RgbaImage src = LoadFile(a.Pos(0, "file"));
            int[] at = Parse.Ints(a.PosOr(1, "0,0"), 2, "position x,y");
            string mode = a.Get("mode", "over").ToLowerInvariant();
            double opacity = Parse.Fraction(a.Get("opacity", "1"), "opacity");
            Composite(Image, src, at[0], at[1], mode, opacity);
        }

        public static void Composite(RgbaImage dst, RgbaImage src, int ox, int oy, string mode, double opacity)
        {
            byte[] d = dst.Pixels, s = src.Pixels;
            if (mode == "clip")
            {
                for (int y = 0; y < dst.Height; y++)
                    for (int x = 0; x < dst.Width; x++)
                    {
                        int di = (y * dst.Width + x) * 4;
                        int sx = x - ox, sy = y - oy;
                        double m = src.Contains(sx, sy) ? s[(sy * src.Width + sx) * 4 + 3] / 255.0 : 0;
                        m = 1 - opacity + opacity * m;
                        d[di + 3] = (byte)Px.Clamp255(d[di + 3] * m);
                    }
                return;
            }
            if (mode != "over" && mode != "under" && mode != "replace" && mode != "erase" && mode != "multiply")
                throw new ImageException("paste: unknown mode '" + mode + "' (over, under, replace, erase, clip, multiply)");
            for (int sy = 0; sy < src.Height; sy++)
                for (int sx = 0; sx < src.Width; sx++)
                {
                    int x = sx + ox, y = sy + oy;
                    if (!dst.Contains(x, y)) continue;
                    int di = (y * dst.Width + x) * 4, si = (sy * src.Width + sx) * 4;
                    double sa = s[si + 3] / 255.0 * opacity;
                    switch (mode)
                    {
                        case "over": Px.Over(d, di, s[si], s[si + 1], s[si + 2], sa); break;
                        case "under":
                            {
                                byte r = d[di], g = d[di + 1], b = d[di + 2];
                                double da = d[di + 3] / 255.0;
                                d[di] = s[si]; d[di + 1] = s[si + 1]; d[di + 2] = s[si + 2]; d[di + 3] = (byte)Px.Clamp255(sa * 255);
                                Px.Over(d, di, r, g, b, da);
                                break;
                            }
                        case "replace": Px.Lerp(d, di, s[si], s[si + 1], s[si + 2], s[si + 3], opacity); break;
                        case "erase": d[di + 3] = (byte)Px.Clamp255(d[di + 3] * (1 - sa)); break;
                        case "multiply":
                            d[di] = (byte)Px.Clamp255(d[di] * (1 - sa + sa * s[si] / 255.0));
                            d[di + 1] = (byte)Px.Clamp255(d[di + 1] * (1 - sa + sa * s[si + 1] / 255.0));
                            d[di + 2] = (byte)Px.Clamp255(d[di + 2] * (1 - sa + sa * s[si + 2] / 255.0));
                            break;
                    }
                }
        }

        // ---- alpha

        void ColorKey(OpArgs a)
        {
            string c = a.PosOr(0, "topleft");
            Rgba key = c.Equals("topleft", StringComparison.OrdinalIgnoreCase) ? Rgba.At(Image, 0, 0) : Parse.Color(c);
            int tol = Parse.Int(a.Get("tolerance", "0"), "tolerance");
            int count = 0;
            byte[] p = Image.Pixels;
            for (int i = 0; i < p.Length; i += 4)
                if (Px.Similar(p, i, key, tol, false) && p[i + 3] != 0) { p[i + 3] = 0; count++; }
            Log.Add("colorkey: " + count + " pixel(s) of " + key.ToRgbString() + " made transparent");
        }

        void Pna(OpArgs a)
        {
            string path = a.PosOr(0, null);
            string full;
            if (path != null) full = ImageIO.Resolve(baseDir, path);
            else
            {
                if (inputPath == null) throw new ImageException("pna: give the .pna file (the input is not a file)");
                full = Path.ChangeExtension(inputPath, ".pna");
            }
            RgbaImage m = ImageIO.Load(full);
            if (m.Width != Image.Width || m.Height != Image.Height)
                throw new ImageException("pna: " + full + " is " + m.Width + "x" + m.Height + ", the image is " + Image.Width + "x" + Image.Height);
            byte[] p = Image.Pixels, q = m.Pixels;
            for (int i = 0; i < p.Length; i += 4) p[i + 3] = (byte)((q[i] + q[i + 1] + q[i + 2] + 1) / 3);
        }

        void Mask(OpArgs a)
        {
            RgbaImage m = LoadFile(a.Pos(0, "mask file"));
            int[] at = Parse.Ints(a.Get("at", "0,0"), 2, "position x,y");
            bool gray = a.Get("channel", "alpha").Equals("gray", StringComparison.OrdinalIgnoreCase);
            bool invert = a.Flag("invert");
            byte[] p = Image.Pixels;
            for (int y = 0; y < Image.Height; y++)
                for (int x = 0; x < Image.Width; x++)
                {
                    int mx = x - at[0], my = y - at[1];
                    double v = 0;
                    if (m.Contains(mx, my))
                    {
                        int mi = (my * m.Width + mx) * 4;
                        v = gray ? Px.Luma(m.Pixels[mi], m.Pixels[mi + 1], m.Pixels[mi + 2]) * m.Pixels[mi + 3] / 255.0 : m.Pixels[mi + 3] / 255.0;
                    }
                    if (invert) v = 1 - v;
                    int i = (y * Image.Width + x) * 4 + 3;
                    p[i] = (byte)Px.Clamp255(p[i] * v);
                }
        }

        void Opacity(OpArgs a)
        {
            double f = Parse.Fraction(a.Pos(0, "factor"), "factor");
            Region region = Region.From(this, a);
            byte[] p = Image.Pixels;
            for (int i = 0, n = 0; i < p.Length; i += 4, n++)
            {
                double t = region.Weight(n);
                p[i + 3] = (byte)Px.Clamp255(p[i + 3] * (1 - t + t * f));
            }
        }

        void Threshold(OpArgs a)
        {
            int level = Parse.Int(a.PosOr(0, "128"), "threshold");
            byte[] p = Image.Pixels;
            for (int i = 3; i < p.Length; i += 4) p[i] = p[i] >= level ? (byte)255 : (byte)0;
        }

        void Flatten(OpArgs a)
        {
            Rgba bg = Parse.Color(a.PosOr(0, "white"));
            byte[] p = Image.Pixels;
            for (int i = 0; i < p.Length; i += 4)
            {
                byte r = p[i], g = p[i + 1], b = p[i + 2];
                double sa = p[i + 3] / 255.0;
                p[i] = bg.R; p[i + 1] = bg.G; p[i + 2] = bg.B; p[i + 3] = 255;
                Px.Over(p, i, r, g, b, sa);
            }
        }

        // ---- color

        sealed class Region
        {
            float[] weights;
            public static Region From(Editor e, OpArgs a)
            {
                Region r = new Region();
                string rect = a.Get("rect", null), mask = a.Get("mask", null);
                if (rect == null && mask == null) return r;
                RgbaImage img = e.Image;
                r.weights = new float[img.Width * img.Height];
                if (rect != null)
                {
                    IntRect rc = Parse.Rect(rect);
                    for (int y = Math.Max(0, rc.Y); y < Math.Min(img.Height, rc.Y + rc.H); y++)
                        for (int x = Math.Max(0, rc.X); x < Math.Min(img.Width, rc.X + rc.W); x++)
                            r.weights[y * img.Width + x] = 1;
                }
                else
                {
                    for (int i = 0; i < r.weights.Length; i++) r.weights[i] = 1;
                }
                if (mask != null)
                {
                    RgbaImage m = e.LoadFile(mask);
                    for (int y = 0; y < img.Height; y++)
                        for (int x = 0; x < img.Width; x++)
                            r.weights[y * img.Width + x] *= m.Contains(x, y) ? m.Pixels[(y * m.Width + x) * 4 + 3] / 255f : 0;
                }
                return r;
            }
            public double Weight(int n) { return weights == null ? 1 : weights[n]; }
        }

        delegate void ColorFunc(ref double r, ref double g, ref double b);

        void PixelMap(OpArgs a, ColorFunc f)
        {
            Region region = Region.From(this, a);
            byte[] p = Image.Pixels;
            for (int i = 0, n = 0; i < p.Length; i += 4, n++)
            {
                double t = region.Weight(n);
                if (t <= 0 || p[i + 3] == 0) continue;
                double r = p[i] / 255.0, g = p[i + 1] / 255.0, b = p[i + 2] / 255.0;
                f(ref r, ref g, ref b);
                p[i] = (byte)Px.Clamp255((p[i] / 255.0 * (1 - t) + Px.Clamp01(r) * t) * 255);
                p[i + 1] = (byte)Px.Clamp255((p[i + 1] / 255.0 * (1 - t) + Px.Clamp01(g) * t) * 255);
                p[i + 2] = (byte)Px.Clamp255((p[i + 2] / 255.0 * (1 - t) + Px.Clamp01(b) * t) * 255);
            }
        }

        void Fill(OpArgs a, bool clear)
        {
            Rgba c = clear ? new Rgba(0, 0, 0, 0) : Parse.Color(a.Pos(0, "color"));
            Region region = Region.From(this, a);
            byte[] p = Image.Pixels;
            for (int i = 0, n = 0; i < p.Length; i += 4, n++) Px.Lerp(p, i, c.R, c.G, c.B, c.A, region.Weight(n));
        }

        void FloodFill(OpArgs a)
        {
            int[] at = Parse.Ints(a.Pos(0, "point x,y"), 2, "point x,y");
            Rgba c = Parse.Color(a.Pos(1, "color"));
            int tol = Parse.Int(a.Get("tolerance", "0"), "tolerance");
            if (!Image.Contains(at[0], at[1])) throw new ImageException("floodfill: " + at[0] + "," + at[1] + " is outside the image");
            int w = Image.Width, h = Image.Height;
            byte[] p = Image.Pixels;
            Rgba seed = Rgba.At(Image, at[0], at[1]);
            bool[] seen = new bool[w * h];
            Stack<int> stack = new Stack<int>();
            stack.Push(at[1] * w + at[0]);
            seen[at[1] * w + at[0]] = true;
            List<int> filled = new List<int>();
            while (stack.Count > 0)
            {
                int n = stack.Pop();
                filled.Add(n);
                int x = n % w, y = n / w;
                int[] nx = { x - 1, x + 1, x, x }, ny = { y, y, y - 1, y + 1 };
                for (int k = 0; k < 4; k++)
                {
                    if (nx[k] < 0 || ny[k] < 0 || nx[k] >= w || ny[k] >= h) continue;
                    int m = ny[k] * w + nx[k];
                    if (seen[m] || !Px.Similar(p, m * 4, seed, tol, true)) continue;
                    seen[m] = true;
                    stack.Push(m);
                }
            }
            foreach (int n in filled) { int i = n * 4; p[i] = c.R; p[i + 1] = c.G; p[i + 2] = c.B; p[i + 3] = c.A; }
            Log.Add("floodfill: " + filled.Count + " pixel(s) like " + seed + " filled");
        }

        void Replace(OpArgs a)
        {
            Rgba from = Parse.Color(a.Pos(0, "color to replace"));
            Rgba to = Parse.Color(a.Pos(1, "new color"));
            int tol = Parse.Int(a.Get("tolerance", "0"), "tolerance");
            Region region = Region.From(this, a);
            byte[] p = Image.Pixels;
            int count = 0;
            for (int i = 0, n = 0; i < p.Length; i += 4, n++)
            {
                double t = region.Weight(n);
                if (t <= 0 || p[i + 3] == 0 || !Px.Similar(p, i, from, tol, false)) continue;
                Px.Lerp(p, i, to.R, to.G, to.B, p[i + 3] * to.A / 255, t);
                count++;
            }
            Log.Add("replace: " + count + " pixel(s) changed");
        }

        void Adjust(OpArgs a)
        {
            double hue = Parse.Number(a.Get("hue", "0"), "hue");
            double sat = Parse.Number(a.Get("sat", "0"), "sat") / 100;
            double light = Parse.Number(a.Get("light", "0"), "light") / 100;
            double bright = Parse.Number(a.Get("bright", "0"), "bright") / 100;
            double contrast = Parse.Number(a.Get("contrast", "0"), "contrast") / 100;
            double gamma = Parse.Number(a.Get("gamma", "1"), "gamma");
            if (gamma <= 0) throw new ImageException("adjust: gamma must be positive");
            bool hsl = hue != 0 || sat != 0 || light != 0;
            PixelMap(a, delegate (ref double r, ref double g, ref double b)
            {
                if (hsl)
                {
                    double h, s, l;
                    Px.ToHsl(r, g, b, out h, out s, out l);
                    h = ((h + hue / 360) % 1 + 1) % 1;
                    s = Px.Clamp01(s * (1 + sat));
                    l = light > 0 ? l + (1 - l) * light : l * (1 + light);
                    Px.FromHsl(h, s, Px.Clamp01(l), out r, out g, out b);
                }
                double k = 1 + bright, c = 1 + contrast;
                r = Px.Clamp01((r * k - 0.5) * c + 0.5); g = Px.Clamp01((g * k - 0.5) * c + 0.5); b = Px.Clamp01((b * k - 0.5) * c + 0.5);
                if (gamma != 1) { r = Math.Pow(r, 1 / gamma); g = Math.Pow(g, 1 / gamma); b = Math.Pow(b, 1 / gamma); }
            });
        }

        void Colorize(OpArgs a)
        {
            Rgba c = Parse.Color(a.Pos(0, "color"));
            double amount = Parse.Fraction(a.Get("amount", "1"), "amount");
            double cr = c.R / 255.0, cg = c.G / 255.0, cb = c.B / 255.0;
            PixelMap(a, delegate (ref double r, ref double g, ref double b)
            {
                double l = 0.299 * r + 0.587 * g + 0.114 * b;
                double tr = l < 0.5 ? cr * 2 * l : cr + (1 - cr) * (2 * l - 1);
                double tg = l < 0.5 ? cg * 2 * l : cg + (1 - cg) * (2 * l - 1);
                double tb = l < 0.5 ? cb * 2 * l : cb + (1 - cb) * (2 * l - 1);
                r += (tr - r) * amount; g += (tg - g) * amount; b += (tb - b) * amount;
            });
        }

        // ---- filters

        void BlurOp(OpArgs a)
        {
            double sigma = Parse.Number(a.Pos(0, "radius"), "radius");
            Region region = Region.From(this, a);
            RgbaImage blurred = Px.Unpremultiply(Px.Blur(Px.Premultiply(Image), Image.Width, Image.Height, sigma), Image.Width, Image.Height);
            byte[] p = Image.Pixels, q = blurred.Pixels;
            for (int i = 0, n = 0; i < p.Length; i += 4, n++) Px.Lerp(p, i, q[i], q[i + 1], q[i + 2], q[i + 3], region.Weight(n));
        }

        void Sharpen(OpArgs a)
        {
            double sigma = Parse.Number(a.PosOr(0, "1"), "radius");
            double amount = Parse.Fraction(a.Get("amount", "1"), "amount");
            Region region = Region.From(this, a);
            RgbaImage blurred = Px.Unpremultiply(Px.Blur(Px.Premultiply(Image), Image.Width, Image.Height, sigma), Image.Width, Image.Height);
            byte[] p = Image.Pixels, q = blurred.Pixels;
            for (int i = 0, n = 0; i < p.Length; i += 4, n++)
            {
                double t = region.Weight(n) * amount;
                if (t <= 0 || p[i + 3] == 0 || q[i + 3] == 0) continue;
                for (int k = 0; k < 3; k++) p[i + k] = (byte)Px.Clamp255(p[i + k] + (p[i + k] - q[i + k]) * t);
            }
        }

        void Outline(OpArgs a)
        {
            double width = Parse.Number(a.Pos(0, "width"), "width");
            Rgba c = Parse.Color(a.Get("color", "black"));
            int w = Image.Width, h = Image.Height, rad = (int)Math.Ceiling(width);
            byte[] p = Image.Pixels;
            RgbaImage layer = new RgbaImage(w, h);
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    double best = 0;
                    for (int dy = -rad; dy <= rad && best < 1; dy++)
                        for (int dx = -rad; dx <= rad; dx++)
                        {
                            int sx = x + dx, sy = y + dy;
                            if (sx < 0 || sy < 0 || sx >= w || sy >= h) continue;
                            double cov = Px.Clamp01(width + 0.5 - Math.Sqrt(dx * dx + dy * dy));
                            double v = p[(sy * w + sx) * 4 + 3] / 255.0 * cov;
                            if (v > best) best = v;
                        }
                    int o = (y * w + x) * 4;
                    layer.Pixels[o] = c.R; layer.Pixels[o + 1] = c.G; layer.Pixels[o + 2] = c.B;
                    layer.Pixels[o + 3] = (byte)Px.Clamp255(best * c.A);
                }
            Composite(layer, Image, 0, 0, "over", 1);
            Image = layer;
        }

        void Shadow(OpArgs a)
        {
            int[] d = Parse.Ints(a.Pos(0, "offset dx,dy"), 2, "offset dx,dy");
            double sigma = Parse.Number(a.Get("blur", "2"), "blur");
            Rgba c = Parse.Color(a.Get("color", "black"));
            double opacity = Parse.Fraction(a.Get("opacity", "0.5"), "opacity");
            int w = Image.Width, h = Image.Height;
            float[] alpha = new float[w * h * 4];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int sx = x - d[0], sy = y - d[1];
                    if (!Image.Contains(sx, sy)) continue;
                    alpha[(y * w + x) * 4 + 3] = Image.Pixels[(sy * w + sx) * 4 + 3] / 255f;
                }
            alpha = Px.Blur(alpha, w, h, sigma);
            RgbaImage layer = new RgbaImage(w, h);
            for (int i = 0; i < w * h; i++)
            {
                int o = i * 4;
                layer.Pixels[o] = c.R; layer.Pixels[o + 1] = c.G; layer.Pixels[o + 2] = c.B;
                layer.Pixels[o + 3] = (byte)Px.Clamp255(alpha[o + 3] * c.A * opacity);
            }
            Composite(layer, Image, 0, 0, "over", 1);
            Image = layer;
        }

        // ---- drawing (GDI+ renders the coverage; the painting itself is done here)

        void Draw(OpArgs a, string shape)
        {
            string mode = a.Get("mode", "over").ToLowerInvariant();
            if (mode != "over" && mode != "replace" && mode != "erase") throw new ImageException(shape + ": unknown mode '" + mode + "' (over, replace, erase)");
            Rgba c = Parse.Color(a.Get("color", "black"));
            bool aa = a.Get("aa", "1") != "0";
            string widthText = a.Get("width", null);
            float penWidth = widthText == null ? 0 : (float)Parse.Number(widthText, "width");
            Action<Graphics> draw;
            switch (shape)
            {
                case "rect":
                case "ellipse":
                    {
                        IntRect r = Parse.Rect(a.Pos(0, "rectangle x,y,w,h"));
                        bool ellipse = shape == "ellipse";
                        draw = delegate (Graphics g)
                        {
                            if (penWidth <= 0)
                            {
                                if (ellipse) g.FillEllipse(Brushes.White, r.X, r.Y, r.W, r.H); else g.FillRectangle(Brushes.White, r.X, r.Y, r.W, r.H);
                            }
                            else
                            {
                                // The stroke stays inside the rectangle.
                                float half = penWidth / 2;
                                using (Pen pen = new Pen(Color.White, penWidth))
                                {
                                    if (ellipse) g.DrawEllipse(pen, r.X + half, r.Y + half, r.W - penWidth, r.H - penWidth);
                                    else g.DrawRectangle(pen, r.X + half, r.Y + half, r.W - penWidth, r.H - penWidth);
                                }
                            }
                        };
                        break;
                    }
                case "line":
                case "polygon":
                    {
                        double[] v = Parse.Numbers(a.Pos(0, "points x1,y1,x2,y2,..."), "points");
                        if (v.Length % 2 != 0 || v.Length < (shape == "line" ? 4 : 6)) throw new ImageException(shape + ": give x1,y1,x2,y2" + (shape == "line" ? ",..." : ",x3,y3,..."));
                        // Points name pixels: pixel (x, y) is centered at (x + 0.5, y + 0.5).
                        PointF[] pts = new PointF[v.Length / 2];
                        for (int i = 0; i < pts.Length; i++) pts[i] = new PointF((float)v[i * 2] + 0.5f, (float)v[i * 2 + 1] + 0.5f);
                        bool line = shape == "line";
                        float lw = penWidth <= 0 ? 1 : penWidth;
                        draw = delegate (Graphics g)
                        {
                            if (!line && penWidth <= 0) { g.FillPolygon(Brushes.White, pts); return; }
                            using (Pen pen = new Pen(Color.White, lw))
                            {
                                pen.LineJoin = LineJoin.Round;
                                pen.StartCap = LineCap.Round;
                                pen.EndCap = LineCap.Round;
                                if (line) g.DrawLines(pen, pts); else g.DrawPolygon(pen, pts);
                            }
                        };
                        break;
                    }
                default:
                    {
                        string text = a.Pos(0, "text");
                        int[] at = Parse.Ints(a.Pos(1, "position x,y"), 2, "position x,y");
                        float size = (float)Parse.Number(a.Get("size", "16"), "size");
                        string fontName = a.Get("font", null);
                        string align = a.Get("align", "left").ToLowerInvariant();
                        FontStyle style = FontStyle.Regular;
                        if (a.Flag("bold")) style |= FontStyle.Bold;
                        if (a.Flag("italic")) style |= FontStyle.Italic;
                        FontFamily family = Gdi.Family(fontName);
                        if (!family.IsStyleAvailable(style)) throw new ImageException("text: the font does not have that style");
                        draw = delegate (Graphics g)
                        {
                            using (Font font = new Font(family, size, style, GraphicsUnit.Pixel))
                            using (StringFormat format = new StringFormat(StringFormat.GenericTypographic))
                            {
                                format.Alignment = align == "center" ? StringAlignment.Center : align == "right" ? StringAlignment.Far : StringAlignment.Near;
                                format.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;
                                g.DrawString(text.Replace("\\n", "\n"), font, Brushes.White, at[0], at[1], format);
                            }
                        };
                        break;
                    }
            }
            float[] cov;
            try { cov = Gdi.Coverage(Image.Width, Image.Height, aa, draw); }
            catch (ImageException) { throw; }
            catch (Exception e) { throw new ImageException(shape + ": drawing failed (" + e.GetType().Name + ": " + e.Message + ")"); }
            byte[] p = Image.Pixels;
            for (int n = 0; n < cov.Length; n++)
            {
                float t = cov[n];
                if (t <= 0) continue;
                int i = n * 4;
                if (mode == "over") Px.Over(p, i, c.R, c.G, c.B, t * c.A / 255.0);
                else if (mode == "replace") Px.Lerp(p, i, c.R, c.G, c.B, c.A, t);
                else p[i + 3] = (byte)Px.Clamp255(p[i + 3] * (1 - t));
            }
        }
    }

    // ---------------------------------------------------------------- commands

    public static class Commands
    {
        public static RgbaImage Open(string baseDir, string spec, out string path)
        {
            path = null;
            if (spec.StartsWith("new:", StringComparison.OrdinalIgnoreCase))
            {
                string rest = spec.Substring(4);
                int colon = rest.IndexOf(':');
                int[] size = Parse.Size(colon < 0 ? rest : rest.Substring(0, colon), false);
                RgbaImage img = new RgbaImage(size[0], size[1]);
                if (colon >= 0)
                {
                    Rgba c = Parse.Color(rest.Substring(colon + 1));
                    for (int i = 0; i < img.Pixels.Length; i += 4) { img.Pixels[i] = c.R; img.Pixels[i + 1] = c.G; img.Pixels[i + 2] = c.B; img.Pixels[i + 3] = c.A; }
                }
                return img;
            }
            path = ImageIO.Resolve(baseDir, spec);
            return ImageIO.Load(path);
        }

        public static string[] Edit(string baseDir, string input, string output, string[] operations)
        {
            string inputPath;
            RgbaImage img = Open(baseDir, input, out inputPath);
            Editor editor = new Editor(img, baseDir, inputPath);
            List<string> log = new List<string>();
            for (int i = 0; i < operations.Length; i++)
            {
                if (string.IsNullOrWhiteSpace(operations[i])) continue;
                try { editor.Apply(operations[i]); }
                catch (ImageException e) { throw new ImageException("operation " + (i + 1) + " (" + operations[i].Trim() + "): " + e.Message); }
                foreach (string line in editor.Log) log.Add(line);
                editor.Log.Clear();
            }
            string outPath = ImageIO.Resolve(baseDir, output);
            ImageIO.Save(editor.Image, outPath);
            log.Add("wrote " + outPath + " (" + editor.Image.Width + "x" + editor.Image.Height + ", 32-bit RGBA PNG)");
            return log.ToArray();
        }

        // selfAlpha: seriko.use_self_alpha of the shell that holds the file ("0" when not set), or null / empty when
        // the file is not in a shell folder. (PowerShell passes $null to a string parameter as an empty string.)
        // baseFile / offset: an image the file is laid over at x,y (as an element or animation part), to check
        // what the file changes there; null / empty to skip.
        public static string[] Info(string baseDir, string file, string[] points, string selfAlpha, string baseFile, string offset)
        {
            string path;
            RgbaImage img = Open(baseDir, file, out path);
            List<string> lines = new List<string>();
            lines.Add((path ?? file) + ":");
            lines.Add("  size: " + img.Width + "x" + img.Height + ", " + img.Format);
            int transparent = 0, partial = 0, opaque = 0;
            HashSet<int> colors = new HashSet<int>();
            byte[] p = img.Pixels;
            for (int i = 0; i < p.Length; i += 4)
            {
                if (p[i + 3] == 0) transparent++; else if (p[i + 3] == 255) opaque++; else partial++;
                if (colors.Count <= 65536) colors.Add(p[i + 3] == 0 ? 0 : (p[i] << 24) | (p[i + 1] << 16) | (p[i + 2] << 8) | p[i + 3]);
            }
            lines.Add("  alpha: transparent " + transparent + ", partial " + partial + ", opaque " + opaque + " (pixels)");
            if (partial > 0)
            {
                int[] bands = new int[4];
                for (int i = 3; i < p.Length; i += 4)
                {
                    int a = p[i];
                    if (a == 0 || a == 255) continue;
                    bands[a < 16 ? 0 : a < 128 ? 1 : a < 240 ? 2 : 3]++;
                }
                lines.Add("  partial alpha: 1-15 (almost invisible) " + bands[0] + ", 16-127 " + bands[1] + ", 128-239 " + bands[2] + ", 240-254 (almost opaque) " + bands[3] + " (pixels)");
            }
            lines.Add("  colors: " + (colors.Count > 65536 ? "more than 65536" : colors.Count.ToString()) + " distinct (RGBA)");
            Rgba topLeft = Rgba.At(img, 0, 0);
            lines.Add("  top-left pixel: " + topLeft);
            // A .pna is a mask for the PNG of the same name, not an image that SSP shows by itself.
            bool isPna = path != null && string.Equals(Path.GetExtension(path), ".pna", StringComparison.OrdinalIgnoreCase);
            if (isPna)
            {
                lines.Add("  .pna: the brightness is the opacity of " + Path.GetFileName(Path.ChangeExtension(path, ".png")) + " (white = opaque, black = transparent)");
                selfAlpha = null;
            }
            bool pna = !isPna && path != null && File.Exists(Path.ChangeExtension(path, ".pna"));
            if (pna) lines.Add("  " + Path.GetFileName(Path.ChangeExtension(path, ".pna")) + " is next to it");
            if (!img.HasAlphaChannel)
            {
                int keyed = 0;
                for (int i = 0; i < p.Length; i += 4) if (Px.Similar(p, i, topLeft, 0, false)) keyed++;
                lines.Add("  top-left color " + topLeft.ToRgbString() + ": " + keyed + " pixel(s)");
            }
            if (!string.IsNullOrEmpty(selfAlpha))
            {
                string mode = selfAlpha == "1" || selfAlpha == "true" ? "1" : selfAlpha == "full" ? "full" : "0";
                string how;
                if (img.HasAlphaChannel && pna && mode != "0") how = "the alpha channel or the .pna (both exist; keep only one)";
                else if (pna) how = "the .pna" + (img.HasAlphaChannel ? "; the alpha channel is ignored" : "");
                else if (img.HasAlphaChannel && mode != "0") how = "the alpha channel";
                else if (mode == "full") how = "nothing: the image is opaque";
                else how = "the top-left color " + topLeft.ToRgbString() + (img.HasAlphaChannel ? "; the alpha channel is ignored" : "");
                if (img.HasTrns && !img.HasAlphaChannel && !pna) how += "; whether SSP uses the tRNS transparency is not documented";
                lines.Add("  in SSP: transparent by " + how + " (seriko.use_self_alpha," + (selfAlpha == "0" ? "0 or not set" : selfAlpha) + ")");
            }
            IntRect? bounds = Px.Bounds(img, 0);
            lines.Add("  visible area (alpha > 0): " + (bounds == null ? "none" : bounds.Value + " (x,y,w,h)"));
            // Without an alpha channel every pixel counts as visible here; SSP cuts such images by the top-left color.
            if (bounds != null && img.HasAlphaChannel) lines.AddRange(Inspect.Islands(img));
            foreach (string pt in points)
            {
                int[] xy = Parse.Ints(pt, 2, "point x,y");
                lines.Add("  pixel " + xy[0] + "," + xy[1] + ": " + (img.Contains(xy[0], xy[1]) ? Rgba.At(img, xy[0], xy[1]).ToString() : "outside the image"));
            }
            if (!string.IsNullOrEmpty(baseFile))
            {
                string basePath;
                RgbaImage baseImg = Open(baseDir, baseFile, out basePath);
                int[] at = string.IsNullOrEmpty(offset) ? new int[] { 0, 0 } : Parse.Ints(offset, 2, "offset x,y");
                lines.Add("  over " + (basePath == null ? baseFile : Path.GetFileName(basePath)) + " at " + at[0] + "," + at[1] + " (coordinates of the base):");
                lines.AddRange(Inspect.OverBase(img, baseImg, at[0], at[1]));
            }
            return lines.ToArray();
        }

        // Compares two images of the same size. Pixels differ when a channel differs by more than the tolerance
        // (two fully transparent pixels are always equal). partOut: the pixels of B that differ, cropped to the
        // bounding box of the differences (the rest transparent), for use as an overlay part.
        public static string[] Diff(string baseDir, string fileA, string fileB, int tolerance, string partOut, string viewOut, out bool different)
        {
            string pathA, pathB;
            RgbaImage a = Open(baseDir, fileA, out pathA), b = Open(baseDir, fileB, out pathB);
            string partPath = string.IsNullOrEmpty(partOut) ? null : ImageIO.Resolve(baseDir, partOut);
            return DiffImages(a, b, "A", "B", tolerance, partPath, viewOut, false, out different);
        }

        // Compares two renderings of the same surface (tools/dump-surface.ps1 -Compare). Returns one line; when
        // they differ and viewOut is given, writes a magnified view of the changed area there.
        public static string Compare(string fileA, string fileB, string labelA, string labelB, string viewOut, out bool different)
        {
            RgbaImage a = ImageIO.Load(fileA), b = ImageIO.Load(fileB);
            return string.Join("; ", DiffImages(a, b, labelA, labelB, 0, null, viewOut, true, out different));
        }

        // cropView: show only the changed area (with a margin), magnified, instead of the whole images.
        static string[] DiffImages(RgbaImage a, RgbaImage b, string labelA, string labelB, int tolerance, string partPath, string viewOut, bool cropView, out bool different)
        {
            List<string> lines = new List<string>();
            different = false;
            if (a.Width != b.Width || a.Height != b.Height)
            {
                different = true;
                lines.Add("sizes differ: " + a.Width + "x" + a.Height + " and " + b.Width + "x" + b.Height + " (only images of the same size are compared)");
                return lines.ToArray();
            }
            // clear: differences above this on a channel are easy to see; smaller ones are not.
            const int clearStep = 32;
            int w = a.Width, h = a.Height, count = 0, largest = 0, clear = 0;
            bool[] diff = new bool[w * h], big = new bool[w * h];
            for (int n = 0; n < w * h; n++)
            {
                int i = n * 4;
                bool same = Px.Similar(a.Pixels, i, new Rgba(b.Pixels[i], b.Pixels[i + 1], b.Pixels[i + 2], b.Pixels[i + 3]), tolerance, true);
                if (same) continue;
                diff[n] = true;
                count++;
                int step = 0;
                for (int c = 0; c < 4; c++) step = Math.Max(step, Math.Abs(a.Pixels[i + c] - b.Pixels[i + c]));
                largest = Math.Max(largest, step);
                if (step > clearStep) { clear++; big[n] = true; }
            }
            if (count == 0)
            {
                lines.Add("identical" + (tolerance > 0 ? " (tolerance " + tolerance + ")" : ""));
                return lines.ToArray();
            }
            different = true;
            int minX = w, minY = h, maxX = -1, maxY = -1;
            for (int n = 0; n < w * h; n++)
            {
                if (!diff[n]) continue;
                int x = n % w, y = n / w;
                minX = Math.Min(minX, x); maxX = Math.Max(maxX, x); minY = Math.Min(minY, y); maxY = Math.Max(maxY, y);
            }
            IntRect box = new IntRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
            lines.Add(count + " pixel(s) differ, within " + box + " (x,y,w,h), " + clear + " of them by more than " + clearStep + ", largest difference " + largest + " (of 255, any channel)");
            if (partPath != null)
            {
                RgbaImage part = new RgbaImage(box.W, box.H);
                for (int y = 0; y < box.H; y++)
                    for (int x = 0; x < box.W; x++)
                    {
                        int n = (y + box.Y) * w + x + box.X;
                        if (diff[n]) Buffer.BlockCopy(b.Pixels, n * 4, part.Pixels, (y * box.W + x) * 4, 4);
                    }
                ImageIO.Save(part, partPath);
                lines.Add("part: " + partPath + " (" + box.W + "x" + box.H + "; paste it at " + box.X + "," + box.Y + ")");
            }
            if (!string.IsNullOrEmpty(viewOut))
            {
                // A in faded gray, the pixels that differ clearly in red, slightly in yellow.
                RgbaImage mark = new RgbaImage(w, h);
                for (int n = 0; n < w * h; n++)
                {
                    int i = n * 4;
                    if (diff[n]) { mark.Pixels[i] = 255; mark.Pixels[i + 1] = (byte)(big[n] ? 0 : 200); mark.Pixels[i + 2] = 0; mark.Pixels[i + 3] = 255; continue; }
                    int l = Px.Clamp255(Px.Luma(a.Pixels[i], a.Pixels[i + 1], a.Pixels[i + 2]) * 255);
                    mark.Pixels[i] = mark.Pixels[i + 1] = mark.Pixels[i + 2] = (byte)(l / 2 + 128);
                    mark.Pixels[i + 3] = (byte)(a.Pixels[i + 3] / 2);
                }
                IntRect? rect = null;
                if (cropView)
                {
                    const int margin = 8;
                    int x0 = Math.Max(0, box.X - margin), y0 = Math.Max(0, box.Y - margin);
                    int x1 = Math.Min(w, box.X + box.W + margin), y1 = Math.Min(h, box.Y + box.H + margin);
                    rect = new IntRect(x0, y0, x1 - x0, y1 - y0);
                }
                lines.Add("view: " + View.Render(new RgbaImage[] { a, b, mark }, new string[] { labelA, labelB, "differences" }, rect, 0, 0, "checker", viewOut));
            }
            return lines.ToArray();
        }
    }

    // ---------------------------------------------------------------- inspection

    public static class Inspect
    {
        const int MaxListed = 10;

        // Groups the visible pixels (alpha > 0) that touch each other, diagonally too. A part cut out of a
        // difference often keeps a few stray pixels away from the rest; the groups are listed smallest first.
        public static List<string> Islands(RgbaImage img)
        {
            int w = img.Width, h = img.Height;
            byte[] p = img.Pixels;
            int[] label = new int[w * h];
            int[] stack = new int[w * h];
            // Each group: minX, minY, maxX, maxY, pixel count, largest alpha.
            List<int[]> groups = new List<int[]>();
            for (int start = 0; start < w * h; start++)
            {
                if (label[start] != 0 || p[start * 4 + 3] == 0) continue;
                int id = groups.Count + 1;
                int[] g = new int[] { w, h, -1, -1, 0, 0 };
                int top = 0;
                stack[top++] = start;
                label[start] = id;
                while (top > 0)
                {
                    int n = stack[--top];
                    int x = n % w, y = n / w;
                    if (x < g[0]) g[0] = x;
                    if (y < g[1]) g[1] = y;
                    if (x > g[2]) g[2] = x;
                    if (y > g[3]) g[3] = y;
                    g[4]++;
                    if (p[n * 4 + 3] > g[5]) g[5] = p[n * 4 + 3];
                    for (int dy = -1; dy <= 1; dy++)
                        for (int dx = -1; dx <= 1; dx++)
                        {
                            int nx = x + dx, ny = y + dy;
                            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                            int m = ny * w + nx;
                            if (label[m] != 0 || p[m * 4 + 3] == 0) continue;
                            label[m] = id;
                            stack[top++] = m;
                        }
                }
                groups.Add(g);
            }
            List<string> lines = new List<string>();
            if (groups.Count == 1)
            {
                lines.Add("  islands: 1 (the visible pixels are all connected)");
                return lines;
            }
            groups.Sort(delegate (int[] u, int[] v) { return u[4] != v[4] ? u[4].CompareTo(v[4]) : u[1] != v[1] ? u[1].CompareTo(v[1]) : u[0].CompareTo(v[0]); });
            int[] big = groups[groups.Count - 1];
            lines.Add("  islands (groups of touching visible pixels): " + groups.Count + "; the largest has " + big[4] + " pixel(s) within " + Box(big) + ". Smallest first:");
            for (int k = 0; k < groups.Count && k < MaxListed; k++)
            {
                int[] g = groups[k];
                lines.Add("    " + Box(g) + ": " + g[4] + " pixel(s), alpha up to " + g[5]);
            }
            if (groups.Count > MaxListed) lines.Add("    ... and " + (groups.Count - MaxListed) + " larger one(s)");
            return lines;
        }

        static string Box(int[] g) { return g[0] + "," + g[1] + "," + (g[2] - g[0] + 1) + "," + (g[3] - g[1] + 1); }

        // A pixel of a part whose alpha is clearly partial (SeamAlphaMin..SeamAlphaMax; below it the base shows,
        // above it the part does) and whose color differs from the base under it by more than SeamColor on a
        // channel shows a mix of two different colors; along the edge of a part that makes a seam.
        const int SeamColor = 48, SeamAlphaMin = 16, SeamAlphaMax = 239;

        // What a part changes when it is laid over the base at ox,oy ("overlay" of surfaces.txt: normal alpha
        // blending). Coordinates in the result are those of the base.
        public static List<string> OverBase(RgbaImage part, RgbaImage baseImg, int ox, int oy)
        {
            int visible = 0, outside = 0, noEffect = 0, changed = 0, largest = 0, overClear = 0, seams = 0;
            int[] changedBox = NewBox(), clearBox = NewBox(), seamBox = NewBox();
            byte[] tmp = new byte[4];
            byte[] s = part.Pixels, d = baseImg.Pixels;
            for (int y = 0; y < part.Height; y++)
                for (int x = 0; x < part.Width; x++)
                {
                    int si = (y * part.Width + x) * 4;
                    int a = s[si + 3];
                    if (a == 0) continue;
                    visible++;
                    int bx = x + ox, by = y + oy;
                    if (!baseImg.Contains(bx, by)) { outside++; continue; }
                    int di = (by * baseImg.Width + bx) * 4;
                    if (d[di + 3] == 0) { overClear++; Grow(clearBox, bx, by); }
                    Buffer.BlockCopy(d, di, tmp, 0, 4);
                    Px.Over(tmp, 0, s[si], s[si + 1], s[si + 2], a / 255.0);
                    int change = 0;
                    for (int c = 0; c < 4; c++) change = Math.Max(change, Math.Abs(tmp[c] - d[di + c]));
                    if (change == 0) noEffect++;
                    else { changed++; largest = Math.Max(largest, change); Grow(changedBox, bx, by); }
                    if (a >= SeamAlphaMin && a <= SeamAlphaMax && d[di + 3] > 0)
                    {
                        int color = Math.Max(Math.Abs(s[si] - d[di]), Math.Max(Math.Abs(s[si + 1] - d[di + 1]), Math.Abs(s[si + 2] - d[di + 2])));
                        if (color > SeamColor) { seams++; Grow(seamBox, bx, by); }
                    }
                }
            List<string> lines = new List<string>();
            lines.Add("    changes " + changed + " pixel(s)" + (changed > 0 ? " within " + Box(changedBox) + ", largest change " + largest + " (of 255, any channel)" : ""));
            if (noEffect > 0) lines.Add("    " + noEffect + " visible pixel(s) change nothing (they could be transparent)");
            if (overClear > 0) lines.Add("    " + overClear + " visible pixel(s) are over transparent pixels of the base, within " + Box(clearBox) + " (they show outside the base)");
            if (outside > 0) lines.Add("    " + outside + " visible pixel(s) are outside the base image");
            if (seams > 0) lines.Add("    " + seams + " pixel(s) with alpha " + SeamAlphaMin + "-" + SeamAlphaMax + " mix a color far from the base (a channel differs by more than " + SeamColor + "), within " + Box(seamBox) + ": look at that edge for a seam");
            if (visible == 0) lines.Add("    (the part has no visible pixel)");
            return lines;
        }

        static int[] NewBox() { return new int[] { int.MaxValue, int.MaxValue, -1, -1 }; }

        static void Grow(int[] box, int x, int y)
        {
            if (x < box[0]) box[0] = x;
            if (y < box[1]) box[1] = y;
            if (x > box[2]) box[2] = x;
            if (y > box[3]) box[3] = y;
        }
    }

    // ---------------------------------------------------------------- preview

    public static class View
    {
        const int Ruler = 18, Gap = 16, Title = 20;

        // background: one background, or several separated by commas; with several, each image gets a row with
        // one panel per background.
        public static string[] Files(string baseDir, string[] files, string rect, int zoom, int grid, string background, string output)
        {
            string[] backgrounds = background.Split(new char[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
            for (int i = 0; i < backgrounds.Length; i++) backgrounds[i] = backgrounds[i].Trim();
            if (backgrounds.Length == 0) backgrounds = new string[] { "checker" };
            List<RgbaImage> images = new List<RgbaImage>();
            List<string> labels = new List<string>();
            List<string> panelBackgrounds = new List<string>();
            foreach (string f in files)
            {
                string path;
                RgbaImage img = Commands.Open(baseDir, f, out path);
                string label = path == null ? f : Path.GetFileName(path);
                foreach (string bg in backgrounds)
                {
                    images.Add(img);
                    labels.Add(backgrounds.Length > 1 ? label + " on " + bg : label);
                    panelBackgrounds.Add(bg);
                }
            }
            IntRect? r = null;
            if (!string.IsNullOrEmpty(rect)) r = Parse.Rect(rect);
            int columns = backgrounds.Length > 1 ? backgrounds.Length : images.Count;
            return new string[] { Render(images.ToArray(), labels.ToArray(), r, zoom, grid, panelBackgrounds.ToArray(), columns, ImageIO.Resolve(baseDir, output)) };
        }

        public static string Render(RgbaImage[] images, string[] labels, IntRect? rect, int zoom, int grid, string background, string output)
        {
            string[] backgrounds = new string[images.Length];
            for (int i = 0; i < backgrounds.Length; i++) backgrounds[i] = background;
            return Render(images, labels, rect, zoom, grid, backgrounds, images.Length, output);
        }

        // Draws the images in rows of the given number of columns, magnified with nearest neighbour, each on its
        // background, with rulers that give the pixel coordinates of the original images. Returns a description
        // of the written file.
        public static string Render(RgbaImage[] images, string[] labels, IntRect? rect, int zoom, int grid, string[] backgrounds, int columns, string output)
        {
            string[] bgs = new string[images.Length];
            Rgba[] bgColors = new Rgba[images.Length];
            for (int i = 0; i < images.Length; i++)
            {
                bgs[i] = backgrounds[i].ToLowerInvariant();
                if (bgs[i] != "checker" && bgs[i] != "alpha" && bgs[i] != "opaque" && bgs[i] != "faint") bgColors[i] = Parse.Color(backgrounds[i]);
            }
            RgbaImage[] views = new RgbaImage[images.Length];
            int ox = 0, oy = 0;
            if (rect != null) { ox = rect.Value.X; oy = rect.Value.Y; }
            int maxSide = 1;
            for (int i = 0; i < images.Length; i++)
            {
                views[i] = rect == null ? images[i] : Px.Crop(images[i], rect.Value.X, rect.Value.Y, rect.Value.W, rect.Value.H, new Rgba(0, 0, 0, 0));
                maxSide = Math.Max(maxSide, Math.Max(views[i].Width, views[i].Height));
            }
            if (zoom <= 0) zoom = Math.Max(1, Math.Min(16, 480 / maxSide));
            if (grid <= 0) grid = zoom >= 12 ? 1 : zoom >= 6 ? 5 : zoom >= 3 ? 10 : 50;
            int labelStep = grid;
            while (labelStep * zoom < 30) labelStep += grid;

            if (columns <= 0 || columns > views.Length) columns = views.Length;
            int rows = (views.Length + columns - 1) / columns;
            int[] colW = new int[columns], rowH = new int[rows];
            for (int k = 0; k < views.Length; k++)
            {
                colW[k % columns] = Math.Max(colW[k % columns], views[k].Width * zoom);
                rowH[k / columns] = Math.Max(rowH[k / columns], views[k].Height * zoom);
            }
            int totalW = Gap, totalH = Gap;
            foreach (int cw in colW) totalW += Ruler + cw + Gap;
            foreach (int rh in rowH) totalH += Title + Ruler + rh + Gap;
            RgbaImage canvas = new RgbaImage(totalW, totalH);
            byte[] c = canvas.Pixels;
            for (int i = 0; i < c.Length; i += 4) { c[i] = 240; c[i + 1] = 240; c[i + 2] = 240; c[i + 3] = 255; }

            List<KeyValuePair<string, PointF>> texts = new List<KeyValuePair<string, PointF>>();
            int top = Gap;
            for (int k = 0; k < views.Length; k++)
            {
                RgbaImage v = views[k];
                string bg = bgs[k];
                Rgba bgColor = bgColors[k];
                int col = k % columns, row = k / columns;
                if (col == 0 && row > 0) top += Title + Ruler + rowH[row - 1] + Gap;
                int left = Gap;
                for (int j = 0; j < col; j++) left += Ruler + colW[j] + Gap;
                int x0 = left + Ruler, y0 = top + Title + Ruler;
                texts.Add(new KeyValuePair<string, PointF>(labels[k] + (rect == null ? "" : " [" + rect.Value + "]") + "  x" + zoom, new PointF(left, top)));
                for (int y = 0; y < v.Height * zoom; y++)
                    for (int x = 0; x < v.Width * zoom; x++)
                    {
                        int si = ((y / zoom) * v.Width + x / zoom) * 4;
                        int di = ((y0 + y) * totalW + x0 + x) * 4;
                        byte[] s = v.Pixels;
                        if (bg == "alpha") { c[di] = c[di + 1] = c[di + 2] = s[si + 3]; continue; }
                        if (bg == "opaque") { c[di] = s[si]; c[di + 1] = s[si + 1]; c[di + 2] = s[si + 2]; continue; }
                        // faint: on the checker, pixels that are there but almost invisible (alpha 1-15) in magenta.
                        if (bg == "faint" && s[si + 3] > 0 && s[si + 3] < 16) { c[di] = 255; c[di + 1] = 0; c[di + 2] = 255; continue; }
                        if (bg == "checker" || bg == "faint")
                        {
                            byte t = ((x / 8 + y / 8) % 2 == 0) ? (byte)255 : (byte)204;
                            c[di] = c[di + 1] = c[di + 2] = t;
                        }
                        else { c[di] = bgColor.R; c[di + 1] = bgColor.G; c[di + 2] = bgColor.B; }
                        Px.Over(c, di, s[si], s[si + 1], s[si + 2], s[si + 3] / 255.0);
                    }
                // Grid lines and ruler ticks.
                for (int gx = 0; gx <= v.Width; gx++)
                {
                    int coord = gx + ox;
                    if (coord % grid != 0) continue;
                    int x = x0 + gx * zoom;
                    if (x >= totalW) continue;
                    bool major = coord % labelStep == 0;
                    for (int y = y0 - (major ? 6 : 3); y < y0; y++) Set(canvas, x, y, 80, 80, 80, 1);
                    if (grid * zoom >= 6) for (int y = y0; y < y0 + v.Height * zoom; y++) Set(canvas, x, y, 0, 160, 255, major ? 0.55 : 0.3);
                    if (major) texts.Add(new KeyValuePair<string, PointF>(coord.ToString(), new PointF(x + 2, y0 - Ruler)));
                }
                for (int gy = 0; gy <= v.Height; gy++)
                {
                    int coord = gy + oy;
                    if (coord % grid != 0) continue;
                    int y = y0 + gy * zoom;
                    if (y >= totalH) continue;
                    bool major = coord % labelStep == 0;
                    for (int x = x0 - (major ? 6 : 3); x < x0; x++) Set(canvas, x, y, 80, 80, 80, 1);
                    if (grid * zoom >= 6) for (int x = x0; x < x0 + v.Width * zoom; x++) Set(canvas, x, y, 0, 160, 255, major ? 0.55 : 0.3);
                    if (major) texts.Add(new KeyValuePair<string, PointF>(coord.ToString(), new PointF(left, y + 1)));
                }
            }
            try
            {
                float[] cov = Gdi.Coverage(totalW, totalH, true, delegate (Graphics g)
                {
                    using (Font title = new Font(FontFamily.GenericSansSerif, 13, FontStyle.Bold, GraphicsUnit.Pixel))
                    using (Font small = new Font(FontFamily.GenericSansSerif, 10, FontStyle.Regular, GraphicsUnit.Pixel))
                    {
                        for (int i = 0; i < texts.Count; i++)
                            g.DrawString(texts[i].Key, i == 0 || texts[i].Key.Contains(" x") ? title : small, Brushes.White, texts[i].Value);
                    }
                });
                for (int n = 0; n < cov.Length; n++) if (cov[n] > 0) Px.Over(c, n * 4, 0, 0, 0, cov[n]);
            }
            catch (Exception) { /* labels need GDI+; the image is still useful without them */ }
            ImageIO.Save(canvas, output);
            return output + " (x" + zoom + ", grid " + grid + ")";
        }

        static void Set(RgbaImage img, int x, int y, int r, int g, int b, double a)
        {
            if (!img.Contains(x, y)) return;
            Px.Over(img.Pixels, (y * img.Width + x) * 4, r, g, b, a);
        }
    }
}
