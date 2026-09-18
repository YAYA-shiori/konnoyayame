<#
.SYNOPSIS
    Starts SSP with this ghost folder ("ssp.exe --ghost <folder>") and waits until the ghost answers SSTP.
.DESCRIPTION
    Runs the working folder directly, without installing the ghost into SSP.
    With SSP 2.8.97 or later, a separate SSP for testing is started with "--option readonly" and
    "--sstp-listen <port>": it saves no settings, history or cache of the author's SSP, does not hand the
    ghost over to an SSP that is already running, and does not delete the folder on vanish. The port is the
    first free one from 9822 to 10999 (or -Port), and it is recorded under the temporary folder, so that
    tools/sstp.ps1 and tools/ssp-log.ps1 send to this SSP while it runs. When it is already running, it is
    left as it is (reload the ghost with "tools/sstp.ps1 -Reload ghost"). -Stop closes it.
    With -Shared, or with older SSP versions, the ghost is handed to the author's SSP instead (port 9801).
    Readiness is checked with "EXECUTE GetName", which must return sakura.name of ghost/master/descript.txt.
    Then the entries that SSP added to its error log while starting are shown (SSP with developer.log
    properties only; see also tools/ssp-log.ps1). With SSP 2.8.94 or later, the log is read after the ghost
    has finished its boot talk ("EXECUTE GetStatus"); older versions get a fixed wait of 2 seconds.
    Exit codes: 0 = the ghost is running (or -Stop closed the SSP or found none), 1 = it did not answer in time
    or the SSP could not be started, 2 = the ghost is running but SSP logged Error or Critical entries,
    3 = ssp.exe was not found.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-ssp.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-ssp.ps1 -Stop
#>
[CmdletBinding()]
param(
    [string]$SspPath,
    # Ghost root folder that contains ghost/ and shell/ (default: this repository).
    [string]$Root,
    # SSTP port (default: the first free port from 9822 for an isolated SSP, 9801 with -Shared).
    [int]$Port = 0,
    # Hand the ghost to the author's SSP instead of starting an isolated one.
    [switch]$Shared,
    # Close the isolated SSP started by this script.
    [switch]$Stop,
    [int]$TimeoutSeconds = 90
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/sstp.ps1')
Initialize-DevkitConsole

if ($Stop) {
    $session = Get-DevkitSspSession
    if (-not $session) {
        Write-Host 'run-ssp: no isolated SSP started by this script is running'
        exit 0
    }
    $process = Get-Process -Id ([int]$session.pid)
    # Close the ghost as the author would, so that OnClose runs and YAYA saves its variables.
    # Owned SSTP: without the ID header, SSP ignores the request as an outside one.
    $sessionName = Get-DevkitDescriptValue (Join-Path $session.root 'ghost/master/descript.txt') 'sakura.name'
    $ghostId = Get-DevkitSspGhostId -GhostRoot $session.root -SakuraName $sessionName -Port $session.port
    if ($ghostId) {
        $lines = @('SEND SSTP/1.4', 'Charset: UTF-8', 'Sender: ghost-devkit', ('ID: ' + $ghostId), 'Script: \-')
        Invoke-DevkitSstp -Lines $lines -Port $session.port -TimeoutSeconds 10 | Out-Null
    }
    if ($process.WaitForExit($TimeoutSeconds * 1000)) {
        Write-Host "run-ssp: closed the isolated SSP (port $($session.port))"
    } else {
        # The isolated SSP saves nothing of its own, so stopping it loses only what the ghost would save on close.
        Stop-Process -Id $process.Id -Force
        Write-Host "run-ssp: the isolated SSP (port $($session.port)) did not close within $TimeoutSeconds seconds, so its process was stopped"
    }
    Remove-DevkitSspSession
    exit 0
}

if (-not $Root) { $Root = $DevkitRoot }
$Root = (Resolve-DevkitFullPath $Root).TrimEnd('\', '/')
$sakuraName = Get-DevkitDescriptValue (Join-Path $Root 'ghost/master/descript.txt') 'sakura.name'

$ssp = Resolve-SspPath $SspPath
if (-not $ssp) {
    Write-Host 'run-ssp: ssp.exe was not found. Set the SSP_PATH environment variable or create tools/local.json (see tools/local.example.json).'
    exit 3
}
$sspVersion = Get-DevkitSspVersion $ssp.Path
$isolated = (-not $Shared) -and $sspVersion -and $sspVersion -ge $DevkitSspIsolatedVersion

$process = $null
if ($isolated) {
    $session = Get-DevkitSspSession
    if ($session) {
        if ([string]$session.root -ine $Root) {
            Write-Host "run-ssp: an isolated SSP for another folder is running (port $($session.port)): $($session.root)"
            Write-Host 'run-ssp: close it first with tools/run-ssp.ps1 -Stop'
            exit 1
        }
        Write-Host "run-ssp: the isolated SSP is already running (SSTP port $($session.port), process $($session.pid))"
        Write-Host 'run-ssp: to load your changes, run tools/sstp.ps1 -Reload ghost. To close it, run tools/run-ssp.ps1 -Stop'
        exit 0
    }
    if ($Port -le 0) {
        $Port = Find-DevkitSspFreePort
        if ($Port -eq 0) {
            Write-Host "run-ssp: no free port from $DevkitSspIsolatedFirstPort to $DevkitSspIsolatedLastPort. Give one with -Port, or use -Shared."
            exit 1
        }
    } elseif (-not (Test-DevkitTcpPortFree $Port)) {
        Write-Host "run-ssp: port $Port is already in use"
        exit 1
    }
    # A new SSP: every entry of its error log comes from this start.
    $marker = [pscustomobject]@{ Kind = 'error'; Name = $null; Total = 0; Key = '' }
    $arguments = @('--option', 'readonly', '--sstp-listen', [string]$Port, '--ghost', ('"' + $Root + '"'))
    $process = Start-Process -FilePath $ssp.Path -ArgumentList $arguments -PassThru
    Save-DevkitSspSession -Process $process -Port $Port -Root $Root -SspPath $ssp.Path
    Write-Host "run-ssp: started an isolated SSP (readonly, SSTP port $Port): $($ssp.Path) --ghost $Root"
} else {
    if (-not $Shared -and $sspVersion) {
        Write-Host "run-ssp: note - SSP $sspVersion is older than $DevkitSspIsolatedVersion, so the ghost runs in your SSP. Update SSP to test it in a separate SSP that saves nothing."
    }
    if ($Port -le 0) { $Port = $DevkitSspDefaultPort }
    # When SSP is already running, only the error log entries added from now on are of interest.
    $marker = New-DevkitSspLogMarker -Kind 'error' -Port $Port
    if (-not $marker) { $marker = [pscustomobject]@{ Kind = 'error'; Name = $null; Total = 0; Key = '' } }

    Start-Process -FilePath $ssp.Path -ArgumentList @('--ghost', ('"' + $Root + '"'))
    Write-Host "run-ssp: started $($ssp.Path) --ghost $Root"
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastResponse = $null
$running = $false
while ((Get-Date) -lt $deadline) {
    if ($process -and $process.HasExited) {
        Remove-DevkitSspSession
        Write-Host "run-ssp: the isolated SSP exited with code $($process.ExitCode) before the ghost answered"
        exit 1
    }
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
    if ($process) { Write-Host 'run-ssp: the isolated SSP is left running; close it with tools/run-ssp.ps1 -Stop' }
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
