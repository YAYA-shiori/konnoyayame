// tamacsw: a window that shows the log of the SHIORI running in SSP (the GUI counterpart of tamacs).
// It loads no dll. SATORI (Mc201-10 and later) looks for a top-level window of the class "TamaWndClass", the class
// of tama (https://github.com/YAYA-shiori/tama), when it sends its first log line after being loaded, and then
// sends each line with WM_COPYDATA: dwData = the log level (the E_* values of tamacs), lpData = the line in UTF-16.
// It looks only once per load, so this window has to be open before the ghost is booted (or booted again).
// Keep this file ASCII-only and within C# 5 (it is compiled with csc.exe of the .NET Framework as a winexe; see
// Get-DevkitTamacsw in tools/lib/common.ps1). Write non-ASCII text with \u escapes.
//
// Usage: tamacsw [-t <window title>]
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

internal static class Tamacsw
{
    internal const string ReceiverClass = "TamaWndClass";

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern IntPtr FindWindowW(string className, string windowName);

    [STAThread]
    static int Main(string[] args)
    {
        string title = null;
        for (int i = 0; i < args.Length; i++)
        {
            if (string.Equals(args[i], "-t", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
                title = args[++i];
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        // Only one window of the class gets the log: tama or another tamacsw may be open.
        if (FindWindowW(ReceiverClass, null) != IntPtr.Zero)
        {
            MessageBox.Show("\u30ED\u30B0\u3092\u53D7\u4FE1\u3059\u308B\u30A6\u30A4\u30F3\u30C9\u30A6\uFF08tama \u304B tamacsw\uFF09\u304C\u3001\u3059\u3067\u306B\u958B\u3044\u3066\u3044\u307E\u3059\u3002",
                "tamacsw", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 1;
        }

        var form = new LogForm(title);
        using (var receiver = new Receiver(form))
        {
            if (!receiver.Created)
            {
                MessageBox.Show("\u30ED\u30B0\u3092\u53D7\u4FE1\u3059\u308B\u30A6\u30A4\u30F3\u30C9\u30A6\u3092\u4F5C\u308C\u307E\u305B\u3093\u3067\u3057\u305F\uFF08\u30A8\u30E9\u30FC " + receiver.Error + "\uFF09\u3002",
                    "tamacsw", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            Application.Run(form);
        }
        return 0;
    }
}

// The hidden top-level window of the class TamaWndClass that SHIORI finds and sends the log to.
// (FindWindow does not find message-only windows, so it is an ordinary window that is never shown.)
internal sealed class Receiver : IDisposable
{
    const uint WM_COPYDATA = 0x004A;

    delegate IntPtr WndProcFn(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WNDCLASSEX
    {
        public uint cbSize;
        public uint style;
        public WndProcFn lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string lpszMenuName;
        public string lpszClassName;
        public IntPtr hIconSm;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct COPYDATASTRUCT
    {
        public IntPtr dwData;
        public int cbData;
        public IntPtr lpData;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern ushort RegisterClassExW(ref WNDCLASSEX wc);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool UnregisterClassW(string className, IntPtr instance);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateWindowExW(uint exStyle, string className, string windowName, uint style,
        int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
    [DllImport("user32.dll")]
    static extern bool DestroyWindow(IntPtr hwnd);
    [DllImport("user32.dll")]
    static extern IntPtr DefWindowProcW(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr GetModuleHandleW(string name);

    readonly LogForm form;
    // Kept in a field so that the delegate is not collected while the window exists.
    readonly WndProcFn wndProc;
    readonly IntPtr instance;
    IntPtr hwnd;
    bool registered;

    public bool Created { get { return hwnd != IntPtr.Zero; } }
    public int Error { get; private set; }

    public Receiver(LogForm form)
    {
        this.form = form;
        wndProc = WndProc;
        instance = GetModuleHandleW(null);
        var wc = new WNDCLASSEX();
        wc.cbSize = (uint)Marshal.SizeOf(typeof(WNDCLASSEX));
        wc.lpfnWndProc = wndProc;
        wc.hInstance = instance;
        wc.lpszClassName = Tamacsw.ReceiverClass;
        if (RegisterClassExW(ref wc) == 0)
        {
            Error = Marshal.GetLastWin32Error();
            return;
        }
        registered = true;
        hwnd = CreateWindowExW(0, Tamacsw.ReceiverClass, "tamacsw", 0, 0, 0, 0, 0,
            IntPtr.Zero, IntPtr.Zero, instance, IntPtr.Zero);
        if (hwnd == IntPtr.Zero)
            Error = Marshal.GetLastWin32Error();
    }

    IntPtr WndProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == WM_COPYDATA && lParam != IntPtr.Zero)
        {
            var cds = (COPYDATASTRUCT)Marshal.PtrToStructure(lParam, typeof(COPYDATASTRUCT));
            string text = "";
            if (cds.lpData != IntPtr.Zero && cds.cbData >= 2)
                text = Marshal.PtrToStringUni(cds.lpData, cds.cbData / 2);
            int nul = text.IndexOf('\0');
            if (nul >= 0)
                text = text.Substring(0, nul);
            // The sender waits for this (SendMessageTimeout), so the line is only queued here.
            form.Enqueue((int)cds.dwData.ToInt64(), text);
            return (IntPtr)1;
        }
        return DefWindowProcW(hwnd, msg, wParam, lParam);
    }

    public void Dispose()
    {
        if (hwnd != IntPtr.Zero)
        {
            DestroyWindow(hwnd);
            hwnd = IntPtr.Zero;
        }
        if (registered)
        {
            UnregisterClassW(Tamacsw.ReceiverClass, instance);
            registered = false;
        }
    }
}

internal sealed class LogForm : Form
{
    // Log levels (the same values as tamacs).
    const int E_I = 0, E_F = 1, E_E = 2, E_W = 3, E_N = 4, E_J = 5, E_END = 6;
    const int E_SJIS = 16, E_UTF8 = 17, E_DEFAULT = 32;

    static readonly string[] LevelPrefix = { "", "[FATAL] ", "[ERROR] ", "[WARN]  ", "[NOTE]  " };

    // The log is always kept short: beyond MaxLength characters, the oldest lines are dropped until KeepLength
    // characters are left. (A text box that reaches its limit stops taking text, as Reshiba's edit box did.)
    const int MaxLength = 1000000;
    const int KeepLength = MaxLength * 3 / 4;
    // Messages kept while paused; the oldest are dropped beyond this.
    const int MaxPending = 20000;

    struct Entry
    {
        public int Mode;
        public string Text;
    }

    readonly RichTextBox log;
    readonly ToolStripStatusLabel status;
    readonly ToolStripMenuItem pauseItem;
    readonly List<Entry> pending = new List<Entry>();
    readonly Timer timer;
    bool paused;
    bool connected;
    // Set when old messages were dropped while paused; noted in the log when it is shown.
    bool dropped;

    public LogForm(string title)
    {
        Text = string.IsNullOrEmpty(title) ? "\u30ED\u30B0\u53D7\u4FE1 - tamacsw" : title + " - \u30ED\u30B0\u53D7\u4FE1";
        ClientSize = new Size(820, 560);
        StartPosition = FormStartPosition.WindowsDefaultLocation;
        KeyPreview = true;

        log = new RichTextBox();
        log.Dock = DockStyle.Fill;
        log.ReadOnly = true;
        // The control itself must never be the limit: Trim keeps the text far below it.
        log.MaxLength = int.MaxValue;
        log.BackColor = SystemColors.Window;
        log.WordWrap = false;
        log.HideSelection = false;
        log.DetectUrls = false;
        log.Font = new Font("MS Gothic", 10f);

        var menu = new MenuStrip();
        var file = new ToolStripMenuItem("\u30D5\u30A1\u30A4\u30EB(&F)");
        file.DropDownItems.Add(Item("\u30ED\u30B0\u3092\u4FDD\u5B58(&S)...", Keys.Control | Keys.S, delegate { SaveLog(); }));
        file.DropDownItems.Add(new ToolStripSeparator());
        file.DropDownItems.Add(Item("\u9589\u3058\u308B(&X)", Keys.None, delegate { Close(); }));
        var edit = new ToolStripMenuItem("\u7DE8\u96C6(&E)");
        edit.DropDownItems.Add(Item("\u30B3\u30D4\u30FC(&C)", Keys.Control | Keys.C, delegate { log.Copy(); }));
        edit.DropDownItems.Add(Item("\u3059\u3079\u3066\u9078\u629E(&A)", Keys.Control | Keys.A, delegate { log.SelectAll(); }));
        var clearItem = Item("\u6D88\u53BB(&L)", Keys.None, delegate { ClearLog(); });
        clearItem.ShortcutKeyDisplayString = "Esc";
        edit.DropDownItems.Add(clearItem);
        var view = new ToolStripMenuItem("\u8868\u793A(&V)");
        pauseItem = Item("\u4E00\u6642\u505C\u6B62(&P)", Keys.F5, delegate { SetPaused(!paused); });
        view.DropDownItems.Add(pauseItem);
        var wrapItem = Item("\u53F3\u7AEF\u3067\u6298\u308A\u8FD4\u3059(&W)", Keys.None, null);
        wrapItem.Click += delegate { wrapItem.Checked = !wrapItem.Checked; log.WordWrap = wrapItem.Checked; };
        view.DropDownItems.Add(wrapItem);
        var topItem = Item("\u5E38\u306B\u624B\u524D\u306B\u8868\u793A(&T)", Keys.None, null);
        topItem.Click += delegate { topItem.Checked = !topItem.Checked; TopMost = topItem.Checked; };
        view.DropDownItems.Add(topItem);
        menu.Items.Add(file);
        menu.Items.Add(edit);
        menu.Items.Add(view);

        var statusStrip = new StatusStrip();
        status = new ToolStripStatusLabel();
        status.Spring = true;
        status.TextAlign = ContentAlignment.MiddleLeft;
        statusStrip.Items.Add(status);

        Controls.Add(log);
        Controls.Add(statusStrip);
        Controls.Add(menu);
        MainMenuStrip = menu;

        timer = new Timer();
        timer.Interval = 100;
        timer.Tick += delegate { Flush(); };
        timer.Start();

        UpdateStatus();
    }

    static ToolStripMenuItem Item(string text, Keys keys, EventHandler onClick)
    {
        var item = new ToolStripMenuItem(text);
        if (keys != Keys.None)
            item.ShortcutKeys = keys;
        if (onClick != null)
            item.Click += onClick;
        return item;
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Escape)
        {
            ClearLog();
            e.Handled = true;
        }
        base.OnKeyDown(e);
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        timer.Stop();
        base.OnFormClosed(e);
    }

    public void Enqueue(int mode, string text)
    {
        pending.Add(new Entry { Mode = mode, Text = text });
        if (pending.Count > MaxPending)
        {
            pending.RemoveRange(0, pending.Count - MaxPending);
            dropped = true;
        }
    }

    void SetPaused(bool value)
    {
        paused = value;
        pauseItem.Checked = paused;
        if (!paused)
            Flush();
        UpdateStatus();
    }

    void ClearLog()
    {
        log.Clear();
    }

    void UpdateStatus()
    {
        string text;
        if (paused)
            text = "\u4E00\u6642\u505C\u6B62\u4E2D\uFF08F5 \u3067\u518D\u958B\uFF09: " + pending.Count + " \u4EF6\u304C\u305F\u307E\u3063\u3066\u3044\u307E\u3059";
        else if (connected)
            text = "\u53D7\u4FE1\u4E2D";
        else
            text = "\u5F85\u6A5F\u4E2D: \u3053\u306E\u30A6\u30A4\u30F3\u30C9\u30A6\u3092\u958B\u3044\u305F\u307E\u307E\u3001\u30B4\u30FC\u30B9\u30C8\u3092\u8D77\u52D5\uFF08\u307E\u305F\u306F\u8D77\u52D5\u3057\u76F4\u3057\uFF09\u3059\u308B\u3068\u3001\u30ED\u30B0\u304C\u5C4A\u304D\u307E\u3059";
        status.Text = text;
    }

    void Flush()
    {
        if (paused)
        {
            if (pending.Count > 0)
                UpdateStatus();
            return;
        }
        if (pending.Count == 0)
            return;

        Entry[] entries = pending.ToArray();
        pending.Clear();

        var run = new StringBuilder();
        Color runColor = SystemColors.GrayText;
        if (dropped)
        {
            run.Append("--- \u4E00\u6642\u505C\u6B62\u4E2D\u306B\u3001\u53E4\u3044\u30ED\u30B0\u3092\u6368\u3066\u307E\u3057\u305F ---\n");
            dropped = false;
        }
        foreach (Entry entry in entries)
        {
            string text;
            Color color;
            if (!Format(entry, out text, out color))
                continue;
            if (run.Length > 0 && color != runColor)
            {
                Append(run.ToString(), runColor);
                run.Length = 0;
            }
            runColor = color;
            run.Append(text);
        }
        if (run.Length > 0)
            Append(run.ToString(), runColor);

        Trim();
        // The caret goes to the end so that the newest line is shown.
        log.SelectionStart = log.TextLength;
        log.SelectionLength = 0;
        log.ScrollToCaret();
        UpdateStatus();
    }

    // Turns one message into the text to show. Returns false for the messages that are not shown.
    bool Format(Entry entry, out string text, out Color color)
    {
        text = null;
        color = SystemColors.WindowText;
        int mode = entry.Mode;
        if (mode == E_SJIS || mode == E_UTF8 || mode == E_DEFAULT)
        {
            // The first notice after SHIORI found this window.
            connected = true;
            return false;
        }
        if (mode == E_END)
        {
            connected = false;
            text = "--- SHIORI \u304C\u30A2\u30F3\u30ED\u30FC\u30C9\u3055\u308C\u307E\u3057\u305F ---\n";
            color = SystemColors.GrayText;
            return true;
        }
        connected = true;
        string line = entry.Text.Replace("\r\n", "\n").Replace('\r', '\n');
        if (!line.EndsWith("\n", StringComparison.Ordinal))
            line += "\n";
        if (mode >= 0 && mode < LevelPrefix.Length)
            line = LevelPrefix[mode] + line;
        text = line;
        if (mode == E_F || mode == E_E)
            color = Color.Red;
        else if (mode == E_W)
            color = Color.DarkOrange;
        else if (mode == E_N)
            color = Color.RoyalBlue;
        return true;
    }

    void Append(string text, Color color)
    {
        log.SelectionStart = log.TextLength;
        log.SelectionLength = 0;
        log.SelectionColor = color;
        log.AppendText(text);
    }

    // Drops the oldest lines when the log is longer than MaxLength, leaving about KeepLength characters.
    void Trim()
    {
        int length = log.TextLength;
        if (length <= MaxLength)
            return;
        int start = length - KeepLength;
        // Cut at the start of the next line; when it is far or there is none, cut anyway, so that the log never grows.
        int cut = log.GetFirstCharIndexFromLine(log.GetLineFromCharIndex(start) + 1);
        if (cut < start || cut > start + 4096)
            cut = start;
        log.ReadOnly = false;
        log.Select(0, cut);
        log.SelectedText = "";
        log.ReadOnly = true;
    }

    void SaveLog()
    {
        using (var dialog = new SaveFileDialog())
        {
            dialog.Filter = "\u30C6\u30AD\u30B9\u30C8 \u30D5\u30A1\u30A4\u30EB (*.txt)|*.txt|\u3059\u3079\u3066\u306E\u30D5\u30A1\u30A4\u30EB (*.*)|*.*";
            dialog.FileName = "shiori-log-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".txt";
            if (dialog.ShowDialog(this) != DialogResult.OK)
                return;
            File.WriteAllText(dialog.FileName, log.Text.Replace("\n", "\r\n"), new UTF8Encoding(false));
        }
    }
}
