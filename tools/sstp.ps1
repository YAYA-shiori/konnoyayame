<#
.SYNOPSIS
    Sends an SSTP request to a running SSP to try talks on the live ghost.
.DESCRIPTION
    By default the request is addressed to this ghost (ReceiverGhostName = sakura.name in
    ghost/master/descript.txt). Use -Ghost to address another ghost, or -AnyGhost for the active one.
    For -Script, -Event and -Reload, the entries that SSP added to its error log in the meantime
    (dictionary errors reported by YAYA, script errors, ...) are shown afterwards. This needs an SSP
    that has the developer.log properties; -NoLog skips it. See also tools/ssp-log.ps1.
    -Script and -Event send "Option: strict", so SSP 2.8.94 or later logs each tag of the played script that
    it could not interpret as "[GHOST/Script] reason (detail) at position n : excerpt".
    SSP answers before the script is played. With SSP 2.8.94 or later, the log is read after the ghost has
    stopped talking ("EXECUTE GetStatus"; up to -TimeoutSeconds), so errors late in a long script are included.
    Older SSP versions get a fixed short wait instead.
    Exit codes: 0 = 2xx response, 1 = error response, 2 = 2xx response but SSP logged Error or Critical
    entries, 3 = could not connect (SSP is not running).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Reload ghost
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Script '\0\s[5]test\e'
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Event OnMouseDoubleClick -Reference '0,0,0,0,Head'
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Execute GetName
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Execute GetStatus
#>
[CmdletBinding(DefaultParameterSetName = 'Script')]
param(
    # Sakura Script to play (single line).
    [Parameter(ParameterSetName = 'Script', Mandatory = $true, Position = 0)]
    [string]$Script,

    # SHIORI event to raise (NOTIFY).
    [Parameter(ParameterSetName = 'Event', Mandatory = $true)]
    [Alias('Event')]
    [string]$EventName,

    # Event references. Commas separate Reference0, Reference1, ...
    [Parameter(ParameterSetName = 'Event')]
    [string[]]$Reference,

    # Reload target for \![reload,...], for example ghost or shiori.
    [Parameter(ParameterSetName = 'Reload', Mandatory = $true)]
    [string]$Reload,

    # EXECUTE command, for example GetName or GetVersion.
    [Parameter(ParameterSetName = 'Execute', Mandatory = $true)]
    [string]$Execute,

    [string]$Ghost,
    [switch]$AnyGhost,
    # Do not show the new SSP error log entries.
    [switch]$NoLog,
    [int]$Port = 9801,
    # Time to wait for the SSTP response, and for the talk to end before the log is read.
    [int]$TimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/sstp.ps1')
Initialize-DevkitConsole

$mode = $PSCmdlet.ParameterSetName
if ($mode -eq 'Reload') { $Script = '\![reload,' + $Reload + ']' }
$ghostRoot = $null
if ($mode -ne 'Execute' -and -not $AnyGhost -and -not $Ghost) {
    $Ghost = Get-DevkitDescriptValue (Join-Path $DevkitRoot 'ghost/master/descript.txt') 'sakura.name'
    $ghostRoot = $DevkitRoot
}

# Owned SSTP: send the ghost's FMO identifier so that SSP does not ignore the request as an outside one.
$ghostId = $null
if ($mode -ne 'Execute' -and -not $AnyGhost) {
    $ghostId = Get-DevkitSspGhostId -GhostRoot $ghostRoot -SakuraName $Ghost -Port $Port
    if (-not $ghostId -and $mode -eq 'Reload') {
        Write-Host "sstp: warning - the FMO identifier of '$Ghost' was not found, so SSP may ignore the reload"
    }
}

$headers = New-Object System.Collections.Generic.List[string]
switch ($mode) {
    'Execute' { $headers.Add('EXECUTE SSTP/1.1') }
    'Event' { $headers.Add('NOTIFY SSTP/1.1') }
    default { $headers.Add('SEND SSTP/1.4') }
}
$headers.Add('Charset: UTF-8')
$headers.Add('Sender: ghost-devkit')
if ($mode -ne 'Execute' -and -not $AnyGhost -and $Ghost) { $headers.Add('ReceiverGhostName: ' + $Ghost) }
if ($ghostId) { $headers.Add('ID: ' + $ghostId) }
# SSP 2.8.94 or later logs the places of the script that it could not interpret. Older versions ignore it.
if ($mode -eq 'Script' -or $mode -eq 'Event') { $headers.Add('Option: strict') }
switch ($mode) {
    'Execute' { $headers.Add('Command: ' + $Execute) }
    'Event' {
        $headers.Add('Event: ' + $EventName)
        $references = @($Reference | Where-Object { $null -ne $_ } | ForEach-Object { $_ -split ',' })
        for ($i = 0; $i -lt $references.Count; $i++) { $headers.Add("Reference${i}: " + $references[$i]) }
    }
    default { $headers.Add('Script: ' + $Script) }
}
foreach ($header in $headers) {
    if ($header -match "[\r\n]") {
        Write-Host 'sstp: values must be a single line'
        exit 1
    }
}

$watchLog = $mode -ne 'Execute' -and -not $NoLog
$marker = $null
$statusAvailable = $false
if ($watchLog) {
    $marker = New-DevkitSspLogMarker -Kind 'error' -Port $Port
    $statusAvailable = $null -ne (Get-DevkitSspStatus $Port)
}

$response = Invoke-DevkitSstp -Lines $headers.ToArray() -Port $Port -TimeoutSeconds $TimeoutSeconds
if (-not $response.Connected) {
    Write-Host "sstp: could not connect to 127.0.0.1:$Port. Is SSP running?"
    exit 3
}

$exitCode = 1
if ($response.TimedOut) {
    Write-Host "sstp: no response within $TimeoutSeconds seconds (the script may still be playing)"
    $exitCode = 0
} else {
    Write-Host $response.Raw.TrimEnd()
    if ($response.Status -ge 200 -and $response.Status -lt 300) {
        $exitCode = 0
    } elseif ($response.Status -eq 404 -and $Ghost) {
        Write-Host "sstp: ghost '$Ghost' was not found. Is it running in SSP? Use -Ghost <sakura name> or -AnyGhost."
    }
}

if ($watchLog -and -not $marker) {
    Write-Host 'sstp: the SSP error log cannot be read (this SSP has no developer.log properties; update SSP to see it)'
} elseif ($watchLog) {
    if ($statusAvailable -and $exitCode -eq 0) {
        # SSP 2.8.94 or later: wait for the reload and for the talk, so that every error of the script is in the log.
        if ($mode -eq 'Reload') {
            $wait = Wait-DevkitSspReload -TimeoutSeconds $TimeoutSeconds -Port $Port
        } else {
            $wait = Wait-DevkitSspTalkEnd -TimeoutSeconds $TimeoutSeconds -Port $Port
        }
        if ($wait -eq 'timeout') { Write-Host "sstp: the ghost is still talking after $TimeoutSeconds seconds; reading the log anyway" }
        Start-Sleep -Milliseconds 300
    } elseif ($mode -eq 'Reload') {
        # Older SSP: the reload runs after the response. Wait until SSP answers again, then give the ghost time to boot.
        Start-Sleep -Milliseconds 1000
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline) {
            $ready = Invoke-DevkitSstp -Lines @('EXECUTE SSTP/1.1', 'Charset: UTF-8', 'Sender: ghost-devkit', 'Command: GetName') -Port $Port -TimeoutSeconds 5
            if ($ready.Status -eq 200) { break }
            Start-Sleep -Milliseconds 500
        }
        Start-Sleep -Milliseconds 1500
    } else {
        Start-Sleep -Milliseconds 500
    }
    $max = 30
    $log = Get-DevkitSspLog -Kind 'error' -Since $marker -Max $max -Port $Port
    $hasError = Write-DevkitSspLogSummary 'sstp' $log $max
    if ($exitCode -eq 0 -and $hasError) { $exitCode = 2 }
}
exit $exitCode
