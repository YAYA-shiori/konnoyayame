<#
.SYNOPSIS
    Runs check-dic, check-shell and lint in order.
.DESCRIPTION
    Exit codes: 0 = all passed (steps whose tool is missing are reported as skipped),
    1 = a step failed, or a step was skipped while -RequireAll is given.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipShell,
    [switch]$SkipLint,
    [switch]$RequireAll
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-DevkitConsole

$steps = New-Object System.Collections.Generic.List[string]
$steps.Add('check-dic')
if (-not $SkipShell) { $steps.Add('check-shell') }
if (-not $SkipLint) { $steps.Add('lint') }

$powershell = (Get-Process -Id $PID).Path
$failed = @()
$skipped = @()
$ErrorActionPreference = 'Continue'
foreach ($step in $steps) {
    Write-Host ''
    Write-Host "==== $step ===="
    & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "$step.ps1")
    $code = $LASTEXITCODE
    if ($code -eq 3) { $skipped += $step } elseif ($code -ne 0) { $failed += $step }
}

Write-Host ''
Write-Host '==== summary ===='
if ($skipped.Count -gt 0) { Write-Host "skipped (tool not available): $($skipped -join ', ')" }
if ($failed.Count -gt 0) {
    Write-Host "FAILED: $($failed -join ', ')"
    exit 1
}
if ($RequireAll -and $skipped.Count -gt 0) { exit 1 }
Write-Host 'all checks passed'
exit 0
