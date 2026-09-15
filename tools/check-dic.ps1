<#
.SYNOPSIS
    Loads the ghost's YAYA dictionaries with tamac.exe and reports load and syntax errors.
.DESCRIPTION
    Exit codes: 0 = OK, 1 = errors found, 3 = tamac.exe is not installed (run tools/setup.ps1).
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
    # Emit GitHub Actions annotations (tamac --ci).
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

$tamac = Get-DevkitToolPath 'tamac'
if (-not (Test-Path -LiteralPath $tamac)) {
    Write-Host 'check-dic: SKIPPED - tamac.exe is not installed. Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1'
    exit 3
}

# Paths in the output are shown relative to the ghost root (the folder with ghost/ and shell/).
$base = Split-Path (Split-Path $GhostDir -Parent) -Parent

$tamacArgs = @()
if ($Level) { $tamacArgs += @('-l', $Level) }
if ($Ci) { $tamacArgs += '--ci' }
$result = Invoke-DevkitTamac -GhostDir $GhostDir -Arguments $tamacArgs -TimeoutSeconds 120

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
    Write-Host 'check-dic: FAILED - tamac.exe timed out'
    exit 1
}
if ($result.ExitCode -ne 0) {
    Write-Host "check-dic: FAILED (tamac.exe exit code $($result.ExitCode)). Fix the errors above; the ghost would start in emergency mode."
    exit 1
}
Write-Host 'check-dic: OK'
exit 0
