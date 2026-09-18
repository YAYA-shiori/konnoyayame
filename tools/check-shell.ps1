<#
.SYNOPSIS
    Checks the shell (surfaces.txt and friends) with "ssp.exe --offline-dump".
.DESCRIPTION
    SSP reports Error / Warning / Notice messages. Notices (for example unused surfaces) are informational.
    SSP 2.8.94 or later is recommended:
      - messages tell where the problem is defined: "[SERIKO] shell/master/surfaces.txt:Line=123:Surface=10 ..."
        (-Ci turns them into annotations on that file and line)
      - the log keeps every entry, without merging similar ones
      - ssp.exe exits with the most severe level logged (0 = Notice or lower, 1 = Warning, 2 = Error,
        3 = Critical), which is checked against the log
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

$sspVersion = Get-DevkitSspVersion $ssp.Path
$levelExitCode = $sspVersion -and $sspVersion -ge $DevkitSspDiagnosticsVersion

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
# SSP 2.8.94 or later exits with 0 to 3 for the most severe level; any other code means that it did not finish.
if (($levelExitCode -and ($result.ExitCode -lt 0 -or $result.ExitCode -gt 3)) -or (-not $levelExitCode -and -not $logWritten -and $result.ExitCode -ne 0)) {
    Write-Host "check-shell: FAILED - ssp.exe exited with code $($result.ExitCode)$(if (-not $logWritten) { ' without writing a log' })"
    exit 1
}

$errors = 0
$warnings = 0
$notices = 0
foreach ($row in $rows) {
    $level = [string]$row.Level
    $message = ConvertTo-DevkitRelativeText ([string]$row.Message) -Base $Root
    # "[SERIKO] <file>:Line=<n>:..." (SSP 2.8.94 or later)
    $place = ''
    if ($message -match '^\[SERIKO\]\s+([^\s(),"]+):Line=(\d+)' -and -not [IO.Path]::IsPathRooted($matches[1])) {
        $place = "file=$($matches[1]),line=$($matches[2]),"
    }
    switch -Regex ($level) {
        '^(error|fatal|critical)$' {
            $errors++
            if ($Ci) { Write-Host "::error ${place}title=SSP shell check::$message" }
        }
        '^warning$' {
            $warnings++
            if ($Ci) { Write-Host "::warning ${place}title=SSP shell check::$message" }
        }
        default { $notices++ }
    }
    Write-Host "[$level] $message"
}

if ($levelExitCode -and $result.ExitCode -ge 2 -and $errors -eq 0) {
    Write-Host "check-shell: ssp.exe exited with code $($result.ExitCode) (Error or Critical), but no such entry was read from the log"
    $errors++
} elseif ($levelExitCode -and $result.ExitCode -eq 1 -and $warnings -eq 0 -and $errors -eq 0) {
    Write-Host 'check-shell: ssp.exe exited with code 1 (Warning), but no warning was read from the log'
    $warnings++
}
if ($sspVersion -and -not $levelExitCode) {
    Write-Host "check-shell: note - SSP $sspVersion is older than $DevkitSspDiagnosticsVersion. Update SSP to see the file and line of each problem and to keep every log entry."
}

$summary = "errors: $errors, warnings: $warnings, notices: $notices"
if ($errors -gt 0 -or ($Strict -and $warnings -gt 0)) {
    Write-Host "check-shell: FAILED ($summary)"
    exit 1
}
Write-Host "check-shell: OK ($summary)"
exit 0
