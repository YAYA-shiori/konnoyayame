// tamacs: loads a SHIORI dll (yaya.dll, satori.dll), prints its log, and optionally sends one request.
// A C# port of tamac.exe (https://github.com/YAYA-shiori/tama) that the kit builds by itself; see
// Get-DevkitTamacs in tools/lib/common.ps1. The command line, the output and the exit codes follow tamac.
// Keep this file ASCII-only and within C# 5 (it is compiled with csc.exe of the .NET Framework, as a 32-bit exe:
// the SHIORI dlls are 32-bit). The same file is used by the YAYA and the SATORI development kits.
//
// Usage: tamacs <shiori dll> [-l fatal|error|warning|note] [--ci] [-r|--request]
//   -l           lowest level of the messages that are shown and make the exit code 2 (default: error)
//   --ci         GitHub Actions annotations (also when the environment variable GITHUB_ACTIONS is set)
//   -r           reads a raw SHIORI request from the standard input until EOF, sends it, and prints the response
//                to the standard output; the log then goes to the standard error
// Exit codes: 0 = OK, 1 = the dll could not be loaded or the request failed (or CI_check_failed with --ci),
//             2 = a message at or above -l was logged, 3 = the dll has no Set_loghandler.
//
// Unlike tamac, the log is received only through Set_loghandler (no window, no logsend): the SHIORI dll must
// export it (YAYA; SATORI since Mc201-10). Requests are always sent in UTF-8 and the charset notices in the log
// are ignored, as tamac does with the log handler: YAYA notifies the charset of its log file, not of the
// requests, and SATORI always notifies UTF-8.
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

internal static class Tamacs
{
    // Log levels of the log handler (the same values as tamac and yaya-CI-check).
    const int E_I = 0, E_F = 1, E_E = 2, E_W = 3, E_N = 4, E_J = 5, E_END = 6;
    const int E_SJIS = 16, E_UTF8 = 17, E_DEFAULT = 32;

    static readonly string[] LevelPrefix = { "", "[FATAL] ", "[ERROR] ", "[WARN]  ", "[NOTE]  " };

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, BestFitMapping = false)]
    static extern IntPtr GetProcAddress(IntPtr module, string name);
    [DllImport("kernel32.dll")]
    static extern bool FreeLibrary(IntPtr module);
    [DllImport("kernel32.dll")]
    static extern IntPtr GlobalAlloc(uint flags, UIntPtr bytes);
    [DllImport("kernel32.dll")]
    static extern IntPtr GlobalFree(IntPtr memory);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int LoadFn(IntPtr h, int len);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int UnloadFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate IntPtr RequestFn(IntPtr h, ref int len);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate int CiCheckFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    delegate void SetLogHandlerFn(LogHandler handler);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    delegate void LogHandler([MarshalAs(UnmanagedType.LPWStr)] string str, int mode, int id);

    static TextWriter stdout;
    static TextWriter stderr;
    static int threshold = E_E;
    static bool detected;
    static bool ciMode;
    static bool requestMode;
    // Kept in a static field so that the delegate is not collected while the dll can call it.
    static LogHandler logHandler;
    static bool inDicLoad, inRequestEnd;

    static readonly Regex FileLineRegex = new Regex(@"\(([0-9]+|-)\) : ");
    static readonly Regex TypeRegex = new Regex(" *([WEN])([0-9]+|-)( *: |\uFF1A)");
    static readonly Regex CommentRegex = new Regex(@"^// *");

    static int Main(string[] args)
    {
        // UTF-8 without BOM, and LF written as CRLF like the text mode of tamac.
        var utf8 = new UTF8Encoding(false);
        stdout = new StreamWriter(Console.OpenStandardOutput(), utf8) { AutoFlush = true, NewLine = "\r\n" };
        stderr = new StreamWriter(Console.OpenStandardError(), utf8) { AutoFlush = true, NewLine = "\r\n" };

        if (args.Length < 1)
        {
            Write(stderr, "Usage: tamacs <shiori dll> [-l fatal|error|warning|note] [--ci] [-r|--request]\n");
            return 1;
        }
        for (int i = 1; i < args.Length; i++)
        {
            string arg = args[i];
            if (Is(arg, "-l") && i + 1 < args.Length)
            {
                int level = ParseLevel(args[++i]);
                if (level < 0)
                {
                    Write(stderr, "Unknown level: " + args[i] + "\n");
                    return 1;
                }
                threshold = level;
            }
            else if (Is(arg, "--ci"))
            {
                ciMode = true;
            }
            else if (Is(arg, "-r") || Is(arg, "--request"))
            {
                requestMode = true;
            }
        }
        if (!ciMode && Environment.GetEnvironmentVariable("GITHUB_ACTIONS") != null)
            ciMode = true;

        string dllPath = Path.GetFullPath(args[0]);
        IntPtr dll = LoadLibraryW(dllPath);
        if (dll == IntPtr.Zero)
        {
            Fail("dll file load failed (" + dllPath + ", error " + Marshal.GetLastWin32Error() + ")");
            return 1;
        }

        var load = Export<LoadFn>(dll, "load");
        var unload = Export<UnloadFn>(dll, "unload");
        var request = Export<RequestFn>(dll, "request");
        var ciCheck = Export<CiCheckFn>(dll, "CI_check_failed");
        var setLogHandler = Export<SetLogHandlerFn>(dll, "Set_loghandler");
        if (load == null || unload == null || request == null)
        {
            if (load == null) Fail("Interface \"load\" not found");
            if (unload == null) Fail("Interface \"unload\" not found");
            if (request == null) Fail("Interface \"request\" not found");
            FreeLibrary(dll);
            return 1;
        }
        if (setLogHandler == null)
        {
            Fail("Interface \"Set_loghandler\" not found; this SHIORI is too old for tamacs");
            FreeLibrary(dll);
            return 3;
        }
        if (ciMode && ciCheck == null)
            Fail("Interface \"CI_check_failed\" not found");

        logHandler = OnLog;
        setLogHandler(logHandler);

        // load() takes the folder of the dll with a trailing separator, in the ANSI code page (as tamac does).
        byte[] dir = Encoding.Default.GetBytes(dllPath.Substring(0, dllPath.LastIndexOfAny(new[] { '\\', '/' }) + 1));
        if (load(ToGlobal(dir), dir.Length) == 0)
        {
            Fail("Interface \"load\" failed");
            FreeLibrary(dll);
            return 1;
        }

        bool ok = true;
        if (requestMode)
            ok = SendRequest(request);

        bool ciFailed = false;
        bool ciChecked = ok && ciMode && ciCheck != null;
        if (ciChecked)
            ciFailed = ciCheck() != 0;

        if (unload() == 0)
            Fail("Interface \"unload\" failed");
        FreeLibrary(dll);

        if (!ok)
            return 1;
        if (ciChecked)
        {
            if (ciFailed)
                Write(LogOut, "::error title=open your tama!::some error in your dic\n");
            return ciFailed ? 1 : 0;
        }
        return detected ? 2 : 0;
    }

    // In request mode the standard output carries only the response, so the log goes to the standard error.
    static TextWriter LogOut { get { return requestMode ? stderr : stdout; } }

    static bool Is(string a, string b)
    {
        return string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    }

    static int ParseLevel(string s)
    {
        if (Is(s, "fatal")) return E_F;
        if (Is(s, "error")) return E_E;
        if (Is(s, "warning")) return E_W;
        if (Is(s, "note")) return E_N;
        return -1;
    }

    static T Export<T>(IntPtr dll, string name) where T : class
    {
        IntPtr p = GetProcAddress(dll, name);
        if (p == IntPtr.Zero) return null;
        return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
    }

    static IntPtr ToGlobal(byte[] bytes)
    {
        IntPtr h = GlobalAlloc(0 /* GMEM_FIXED */, (UIntPtr)(uint)Math.Max(bytes.Length, 1));
        if (h == IntPtr.Zero) throw new OutOfMemoryException("GlobalAlloc failed");
        Marshal.Copy(bytes, 0, h, bytes.Length);
        return h;
    }

    static void Fail(string message)
    {
        Write(stderr, "[tamacs] " + message + "\n");
    }

    // Writes text, turning every line break into CRLF.
    static void Write(TextWriter writer, string text)
    {
        writer.Write(text.Replace("\r\n", "\n").Replace("\n", "\r\n"));
    }

    // Reads the standard input until EOF and shapes it into a SHIORI request (CRLF line breaks, ending with a
    // blank line). Returns "" when the input has only blank lines.
    static string ReadRequest()
    {
        var bytes = new MemoryStream();
        using (Stream input = Console.OpenStandardInput())
            input.CopyTo(bytes);
        string text = new UTF8Encoding(false).GetString(bytes.ToArray());
        if (text.Length > 0 && text[0] == '\uFEFF')
            text = text.Substring(1);

        var lines = new List<string>(text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'));
        while (lines.Count > 0 && lines[lines.Count - 1].Length == 0)
            lines.RemoveAt(lines.Count - 1);
        if (lines.Count == 0)
            return "";
        return string.Join("\r\n", lines.ToArray()) + "\r\n\r\n";
    }

    static bool SendRequest(RequestFn request)
    {
        string req = ReadRequest();
        if (req.Length == 0)
        {
            Fail("empty request");
            return false;
        }
        byte[] bytes = Encoding.UTF8.GetBytes(req);
        int len = bytes.Length;
        IntPtr res = request(ToGlobal(bytes), ref len);
        string response = "";
        if (res != IntPtr.Zero)
        {
            if (len > 0)
            {
                var buffer = new byte[len];
                Marshal.Copy(res, buffer, 0, len);
                response = Encoding.UTF8.GetString(buffer);
            }
            GlobalFree(res);
        }
        if (response.Length == 0)
        {
            Fail("empty response");
            return false;
        }
        Write(stdout, response);
        return true;
    }

    static void OnLog(string str, int mode, int id)
    {
        if (str == null) return;
        if (mode >= E_F && mode <= threshold)
            detected = true;
        if (ciMode)
            WriteCi(str, mode, id);
        else
            WritePlain(str, mode);
    }

    static void WritePlain(string str, int mode)
    {
        if (mode == E_SJIS || mode == E_UTF8 || mode == E_DEFAULT || mode == E_END) return;
        if (mode >= E_F && mode > threshold) return;
        TextWriter output = (mode >= E_F && mode <= E_W) ? stderr : LogOut;
        if (mode >= 0 && mode < LevelPrefix.Length)
            Write(output, LevelPrefix[mode]);
        Write(output, str);
    }

    // GitHub Actions annotations, as tamac --ci (which follows check-tool.cpp of YAYA-shiori/yaya-CI-check).
    static void WriteCi(string str, int mode, int id)
    {
        if (mode == E_SJIS || mode == E_UTF8 || mode == E_DEFAULT || mode == E_END) return;

        string type = "", info = "", filename = "";
        long line = 0;
        // Example: path\to\file.dic(17) : error E0041 : message
        Match m = FileLineRegex.Match(str);
        if (m.Success)
        {
            filename = str.Substring(0, m.Index);
            long.TryParse(m.Groups[1].Value, out line);
            info = str.Substring(m.Index + m.Length);
            Match t = TypeRegex.Match(info);
            if (t.Success)
            {
                type = info.Substring(0, t.Index);
                info = info.Substring(t.Index + t.Length);
            }
        }
        if (mode >= E_F && mode <= E_N)
        {
            if (type.Length == 0)
                type = mode == E_F ? "fatal" : mode == E_E ? "error" : mode == E_W ? "warning" : "notice";
            if (info.Length == 0) info = str;
            info = CommentRegex.Replace(info, "").TrimEnd('\r', '\n');
        }
        string location = "file=" + filename + ",line=" + line + ",title=" + type + "::" + info + "\n";

        switch (mode)
        {
            case E_I:
                if (str == "// request\n")
                {
                    Write(LogOut, "::group::request call\n");
                }
                else if (!inRequestEnd && str.StartsWith("// response (Execution time : ", StringComparison.Ordinal))
                {
                    inRequestEnd = true;
                }
                else if (inRequestEnd && str == "\n")
                {
                    inRequestEnd = false;
                    Write(LogOut, "::endgroup::\n");
                }
                if (inDicLoad && id == 8) // end of the dictionary list
                {
                    inDicLoad = false;
                    Write(LogOut, "::endgroup::\n");
                }
                Write(LogOut, str);
                if (id == 3) // start of the dictionary list
                {
                    inDicLoad = true;
                    Write(LogOut, "::group::dic load list\n");
                }
                break;
            case E_F:
                Write(stderr, str);
                Write(stderr, "::error " + location);
                break;
            case E_E:
                if (id == 57)
                {
                    // E0057 is always ignored in CI checks
                    Write(LogOut, str);
                    Write(LogOut, "// from CI checker: E0057 is always ignored in CI check\n");
                }
                else
                {
                    Write(stderr, str);
                    if (id == 10) // emergency mode
                        Write(stderr, "::error title=Emergency mode::Goes into emergency mode\n");
                    else
                        Write(stderr, "::error " + location);
                }
                break;
            case E_W:
                Write(stderr, str);
                Write(stderr, "::warning " + location);
                break;
            case E_N:
                if (id == 0)
                {
                    // N0000 is always ignored in CI checks
                    Write(LogOut, str);
                    Write(LogOut, "// from CI checker: N0000 is always ignored in CI check\n");
                }
                else
                {
                    Write(stderr, str);
                    Write(stderr, "::notice " + location);
                }
                break;
            case E_J:
                Write(LogOut, str);
                break;
        }
    }
}
