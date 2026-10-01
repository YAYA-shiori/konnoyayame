<#
.SYNOPSIS
    Loads the ghost's YAYA dictionaries with tamacs.exe and reports load and syntax errors.
.DESCRIPTION
    Exit codes: 0 = OK, 1 = errors found, 3 = not checked (tamacs.exe could not be built, or
    yaya.dll is too old to have Set_loghandler).
    tamacs.exe is built from tools/lib/tamacs.cs on the first run (Get-DevkitTamacs in tools/lib/common.ps1).
    Loading YAYA rewrites ghost/master/yaya_variable.cfg, so the file is restored afterwards.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-dic.ps1
#>
[CmdletBinding()]
param(
    # Folder that contains yaya.dll (default: ghost/master).
    [string]$GhostDir,
    [ValidateSet('fatal', 'error', 'warning', 'note')]
    [string]$Level,
    # Emit GitHub Actions annotations (tamacs --ci).
    [switch]$Ci,
    # Also print the YAYA load log.
    [switch]$ShowLog
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-DevkitConsole

if (-not $GhostDir) { $GhostDir = Join-Path $DevkitRoot 'ghost/master' }
$GhostDir = (Resolve-DevkitFullPath $GhostDir).TrimEnd('\', '/')
$dll = Join-Path $GhostDir 'yaya.dll'
if (-not (Test-Path -LiteralPath $dll)) {
    Write-Host "check-dic: FAILED - yaya.dll was not found in $GhostDir"
    exit 1
}

$tamacs = Get-DevkitTamacs
if (-not $tamacs.Path) {
    Write-Host "check-dic: SKIPPED - $($tamacs.Error)"
    exit 3
}

# Paths in the output are shown relative to the ghost root (the folder with ghost/ and shell/).
$base = Split-Path (Split-Path $GhostDir -Parent) -Parent

$tamacArgs = @()
if ($Level) { $tamacArgs += @('-l', $Level) }
if ($Ci) { $tamacArgs += '--ci' }
$result = Invoke-DevkitTamacs -GhostDir $GhostDir -Arguments $tamacArgs -TimeoutSeconds 120

if ($ShowLog -or $Ci) {
    foreach ($line in ($result.StdOut -split "\r?\n")) {
        Write-Host (ConvertTo-DevkitRelativeText $line -Base $base)
    }
}

$diagnostics = @(($result.StdErr -split "\r?\n") | Where-Object { $_.Trim() -ne '' })
foreach ($line in $diagnostics) {
    Write-Host (ConvertTo-DevkitRelativeText $line -Base $base)
}

if ($result.TimedOut) {
    Write-Host 'check-dic: FAILED - tamacs.exe timed out'
    exit 1
}
if ($result.ExitCode -eq 3) {
    Write-Host 'check-dic: SKIPPED - yaya.dll has no Set_loghandler, which tamacs.exe needs. Update yaya.dll: docs/agents/workflows/update-yaya.md'
    exit 3
}
if ($result.ExitCode -ne 0) {
    Write-Host "check-dic: FAILED (tamacs.exe exit code $($result.ExitCode)). Fix the errors above; the ghost would start in emergency mode."
    exit 1
}
Write-Host 'check-dic: OK'
exit 0
