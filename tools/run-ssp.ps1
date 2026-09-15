<#
.SYNOPSIS
    Starts SSP with this ghost folder ("ssp.exe --ghost <folder>") and waits until the ghost answers SSTP.
.DESCRIPTION
    Runs the working folder directly, without installing the ghost into SSP.
    Readiness is checked with "EXECUTE GetName", which must return sakura.name of ghost/master/descript.txt.
    Then the entries that SSP added to its error log while starting are shown (SSP with developer.log
    properties only; see also tools/ssp-log.ps1). With SSP 2.8.94 or later, the log is read after the ghost
    has finished its boot talk ("EXECUTE GetStatus"); older versions get a fixed wait of 2 seconds.
    Exit codes: 0 = the ghost is running, 1 = it did not answer in time, 2 = the ghost is running but SSP
    logged Error or Critical entries, 3 = ssp.exe was not found.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-ssp.ps1
#>
[CmdletBinding()]
param(
    [string]$SspPath,
    # Ghost root folder that contains ghost/ and shell/ (default: this repository).
    [string]$Root,
    [int]$Port = 9801,
    [int]$TimeoutSeconds = 90
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/sstp.ps1')
Initialize-DevkitConsole

if (-not $Root) { $Root = $DevkitRoot }
$Root = (Resolve-DevkitFullPath $Root).TrimEnd('\', '/')
$sakuraName = Get-DevkitDescriptValue (Join-Path $Root 'ghost/master/descript.txt') 'sakura.name'

$ssp = Resolve-SspPath $SspPath
if (-not $ssp) {
    Write-Host 'run-ssp: ssp.exe was not found. Set the SSP_PATH environment variable or create tools/local.json (see tools/local.example.json).'
    exit 3
}

# When SSP is already running, only the error log entries added from now on are of interest.
$marker = New-DevkitSspLogMarker -Kind 'error' -Port $Port
if (-not $marker) { $marker = [pscustomobject]@{ Kind = 'error'; Name = $null; Total = 0; Key = '' } }

Start-Process -FilePath $ssp.Path -ArgumentList @('--ghost', ('"' + $Root + '"'))
Write-Host "run-ssp: started $($ssp.Path) --ghost $Root"

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastResponse = $null
$running = $false
while ((Get-Date) -lt $deadline) {
    $response = Invoke-DevkitSstp -Lines @('EXECUTE SSTP/1.1', 'Charset: UTF-8', 'Sender: ghost-devkit', 'Command: GetName') -Port $Port -TimeoutSeconds 5
    $lastResponse = $response.Raw
    if ($response.Status -eq 200 -and (-not $sakuraName -or $lastResponse.Contains($sakuraName))) {
        $running = $true
        break
    }
    Start-Sleep -Milliseconds 1000
}
if (-not $running) {
    if ($lastResponse) {
        Write-Host "run-ssp: SSP answers, but '$sakuraName' is not the current ghost. Last GetName response:"
        Write-Host $lastResponse.TrimEnd()
    } else {
        Write-Host "run-ssp: SSTP did not answer on port $Port within $TimeoutSeconds seconds"
    }
    exit 1
}
Write-Host "run-ssp: the ghost is running (SSTP port $Port)"

# Give the ghost time to boot and finish its first talk, so that errors reported on its first events are in the log.
$wait = Wait-DevkitSspTalkEnd -StartSeconds 2 -TimeoutSeconds 60 -Port $Port
if ($wait -eq 'unsupported') {
    Start-Sleep -Milliseconds 2000
} else {
    if ($wait -eq 'timeout') { Write-Host 'run-ssp: the ghost is still talking after 60 seconds; reading the log anyway' }
    Start-Sleep -Milliseconds 300
}
$max = 30
$log = Get-DevkitSspLog -Kind 'error' -Since $marker -Max $max -Port $Port
if ($log.State -ne 'ok') {
    Write-Host 'run-ssp: the SSP error log cannot be read (this SSP has no developer.log properties; update SSP to see it)'
    exit 0
}
if (Write-DevkitSspLogSummary 'run-ssp' $log $max -Base $Root) { exit 2 }
exit 0
