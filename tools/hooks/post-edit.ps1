# Claude Code PostToolUse hook (see .claude/settings.json).
# After a ghost file is edited, runs the matching checker. When the checker fails, its output is
# written to stderr with exit code 2 so that Claude sees the problem and fixes it.
# Missing tools (exit code 3) are skipped silently.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/common.ps1')
Initialize-DevkitConsole

try {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $DevkitUtf8)
    $payload = $reader.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

$filePath = $null
if ($payload.tool_input -and $payload.tool_input.file_path) { $filePath = [string]$payload.tool_input.file_path }
if (-not $filePath) { exit 0 }

$fullPath = [IO.Path]::GetFullPath($filePath)
$rootWithSeparator = $DevkitRoot + [IO.Path]::DirectorySeparatorChar
if (-not $fullPath.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) { exit 0 }
$relative = $fullPath.Substring($rootWithSeparator.Length).Replace('\', '/')

$step = $null
if ($relative -like 'ghost/*' -and ($relative -like '*.dic' -or $relative -like '*.txt')) {
    $step = 'check-dic.ps1'
} elseif ($relative -like 'shell/*' -and $relative -like '*.txt') {
    $step = 'check-shell.ps1'
}
if (-not $step) { exit 0 }

$powershell = (Get-Process -Id $PID).Path
$result = Invoke-DevkitProcess -FilePath $powershell -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $DevkitToolsDir $step)) -TimeoutSeconds 240
if ($result.ExitCode -eq 0 -or $result.ExitCode -eq 3) { exit 0 }

$message = "tools/$step failed after editing $relative. Fix the problem before continuing.`n" + $result.StdOut + $result.StdErr
[Console]::Error.WriteLine($message.TrimEnd())
exit 2
