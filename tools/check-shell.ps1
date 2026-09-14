<#
.SYNOPSIS
    Checks the shell (surfaces.txt and friends) with "ssp.exe --offline-dump".
.DESCRIPTION
    SSP reports Error / Warning / Notice messages. Notices (for example unused surfaces) are informational.
    Exit codes: 0 = OK, 1 = errors found (or warnings with -Strict), 3 = ssp.exe was not found.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-shell.ps1
#>
[CmdletBinding()]
param(
    [string]$SspPath,
    # Ghost root folder that contains ghost/ and shell/ (default: this repository).
    [string]$Root,
    # Treat warnings as failures.
    [switch]$Strict,
    # Emit GitHub Actions annotations.
    [switch]$Ci
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-DevkitConsole

if (-not $Root) { $Root = $DevkitRoot }
$Root = (Resolve-DevkitFullPath $Root).TrimEnd('\', '/')

$ssp = Resolve-SspPath $SspPath
if (-not $ssp) {
    Write-Host 'check-shell: SKIPPED - ssp.exe was not found. Set the SSP_PATH environment variable or create tools/local.json (see tools/local.example.json).'
    exit 3
}

$log = Join-Path ([IO.Path]::GetTempPath()) ('devkit-ssp-' + [guid]::NewGuid().ToString('N') + '.log')
$result = Invoke-DevkitProcess -FilePath $ssp.Path -Arguments @('--offline-dump', $Root, '--dump-error-log', $log) -TimeoutSeconds 180
$rows = @()
$logWritten = Test-Path -LiteralPath $log
if ($logWritten) {
    $rows = @(Import-Csv -LiteralPath $log -Header 'Time', 'Name', 'Level', 'Message' -Encoding UTF8)
    Remove-Item -LiteralPath $log -Force
}

if ($result.TimedOut) {
    Write-Host 'check-shell: FAILED - ssp.exe timed out'
    exit 1
}
if (-not $logWritten -and $result.ExitCode -ne 0) {
    Write-Host "check-shell: FAILED - ssp.exe exited with code $($result.ExitCode) without writing a log"
    exit 1
}

$errors = 0
$warnings = 0
$notices = 0
foreach ($row in $rows) {
    $level = [string]$row.Level
    $message = ConvertTo-DevkitRelativeText ([string]$row.Message) -Base $Root
    switch -Regex ($level) {
        '^(error|fatal|critical)$' {
            $errors++
            if ($Ci) { Write-Host "::error title=SSP shell check::$message" }
        }
        '^warning$' {
            $warnings++
            if ($Ci) { Write-Host "::warning title=SSP shell check::$message" }
        }
        default { $notices++ }
    }
    Write-Host "[$level] $message"
}

$summary = "errors: $errors, warnings: $warnings, notices: $notices"
if ($errors -gt 0 -or ($Strict -and $warnings -gt 0)) {
    Write-Host "check-shell: FAILED ($summary)"
    exit 1
}
Write-Host "check-shell: OK ($summary)"
exit 0
