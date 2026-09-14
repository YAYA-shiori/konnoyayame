<#
.SYNOPSIS
    Starts SSP with this ghost folder ("ssp.exe --ghost <folder>") and waits until the ghost answers SSTP.
.DESCRIPTION
    Runs the working folder directly, without installing the ghost into SSP.
    Readiness is checked with "EXECUTE GetName", which must return sakura.name of ghost/master/descript.txt.
    Exit codes: 0 = the ghost is running, 1 = it did not answer in time, 3 = ssp.exe was not found.
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
Initialize-DevkitConsole

if (-not $Root) { $Root = $DevkitRoot }
$Root = (Resolve-DevkitFullPath $Root).TrimEnd('\', '/')
$sakuraName = Get-DevkitDescriptValue (Join-Path $Root 'ghost/master/descript.txt') 'sakura.name'

$ssp = Resolve-SspPath $SspPath
if (-not $ssp) {
    Write-Host 'run-ssp: ssp.exe was not found. Set the SSP_PATH environment variable or create tools/local.json (see tools/local.example.json).'
    exit 3
}

Start-Process -FilePath $ssp.Path -ArgumentList @('--ghost', ('"' + $Root + '"'))
Write-Host "run-ssp: started $($ssp.Path) --ghost $Root"

function Get-SstpGhostName {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect('127.0.0.1', $Port)
        $client.ReceiveTimeout = 5000
        $stream = $client.GetStream()
        $bytes = $DevkitUtf8.GetBytes("EXECUTE SSTP/1.1`r`nCharset: UTF-8`r`nSender: ghost-devkit`r`nCommand: GetName`r`n`r`n")
        $stream.Write($bytes, 0, $bytes.Length)
        return (New-Object System.IO.StreamReader($stream, $DevkitUtf8)).ReadToEnd()
    } catch {
        return $null
    } finally {
        $client.Close()
    }
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastResponse = $null
while ((Get-Date) -lt $deadline) {
    $lastResponse = Get-SstpGhostName
    if ($lastResponse -and $lastResponse -match '^SSTP/\d\.\d 200' -and (-not $sakuraName -or $lastResponse.Contains($sakuraName))) {
        Write-Host "run-ssp: the ghost is running (SSTP port $Port)"
        exit 0
    }
    Start-Sleep -Milliseconds 1000
}
if ($lastResponse) {
    Write-Host "run-ssp: SSP answers, but '$sakuraName' is not the current ghost. Last GetName response:"
    Write-Host $lastResponse.TrimEnd()
} else {
    Write-Host "run-ssp: SSTP did not answer on port $Port within $TimeoutSeconds seconds"
}
exit 1
