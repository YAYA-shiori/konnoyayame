<#
.SYNOPSIS
    Sends an SSTP request to a running SSP to try talks on the live ghost.
.DESCRIPTION
    By default the request is addressed to this ghost (ReceiverGhostName = sakura.name in
    ghost/master/descript.txt). Use -Ghost to address another ghost, or -AnyGhost for the active one.
    For -Script, -Event and -Reload, the entries that SSP added to its error log in the meantime
    (dictionary errors reported by YAYA, script errors, ...) are shown afterwards. This needs an SSP
    that has the developer.log properties; -NoLog skips it. See also tools/ssp-log.ps1.
    -Script and -Event send "Option: strict", so SSP logs each tag of the played script that
    it could not interpret as "[GHOST/Script] reason (detail) at position n : excerpt".
    SSP answers before the script is played. The log is read after the ghost has stopped talking
    ("EXECUTE GetStatus"; up to -TimeoutSeconds), so errors late in a long script are included. When GetStatus
    does not answer (for example while the ghost is being loaded), a fixed short wait is used instead.
    Exit codes: 0 = 2xx response, 1 = error response, 2 = 2xx response but SSP logged Error or Critical
    entries, 3 = could not connect (SSP is not running).
    While the isolated SSP started by tools/run-ssp.ps1 runs, requests go to its port unless -Port is given.
    -Balloon (with -Script or -Event) writes what the balloons show after the talk to PNG files
    (balloon0.png for \0, balloon1.png for \1, ...), so that line breaks and lines too long for the balloon can be
    looked at. After the ghost has stopped talking, it sends "\C\![execute,dumpballoon,...]" (\C keeps the
    balloons as they are). SSP writes the images only under the folders it manages, so they are written to a
    temporary folder under ghost/master of the running ghost first, then moved to ghost-devkit/balloons-<hash> in the
    temp folder (its PNG files are removed before each run). A scope without a balloon writes no image.
    When -Balloon writes no image, the exit code is 2.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Reload ghost
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Script '\0\s[5]test\e'
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Event OnMouseDoubleClick -Reference '0,0,0,0,Head'
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Script '\0\s[5]test\w8\1\s[10]test\e' -Balloon
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
    # After the talk, write the balloons to PNG files (-Script and -Event only).
    [switch]$Balloon,
    # Scope IDs of the balloons for -Balloon, separated by commas (default 0 and 1). A string, because
    # [int[]] would read "0,1,2" given through -File as the number 12.
    [string[]]$BalloonScope = @('0', '1'),
    # SSTP port (default: the isolated SSP started by tools/run-ssp.ps1 while it runs, otherwise 9801).
    [int]$Port = 0,
    # Time to wait for the SSTP response, and for the talk to end before the log is read.
    [int]$TimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/sstp.ps1')
Initialize-DevkitConsole
$Port = Resolve-DevkitSspPort $Port

$mode = $PSCmdlet.ParameterSetName
if ($Balloon -and ($mode -eq 'Reload' -or $mode -eq 'Execute')) {
    Write-Host 'sstp: -Balloon works only with -Script and -Event'
    exit 1
}
if ($Balloon -and $AnyGhost) {
    Write-Host 'sstp: -Balloon needs to know the ghost; use -Ghost <sakura name> instead of -AnyGhost'
    exit 1
}
$BalloonScope = @($BalloonScope | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Balloon -and ($BalloonScope.Count -eq 0 -or @($BalloonScope | Where-Object { $_ -notmatch '^\d+$' }).Count -gt 0)) {
    Write-Host 'sstp: -BalloonScope takes scope IDs such as 0,1'
    exit 1
}
if ($mode -eq 'Reload') { $Script = '\![reload,' + $Reload + ']' }
$ghostRoot = $null
if ($mode -ne 'Execute' -and -not $AnyGhost -and -not $Ghost) {
    $Ghost = Get-DevkitDescriptValue (Join-Path $DevkitRoot 'ghost/master/descript.txt') 'sakura.name'
    $ghostRoot = $DevkitRoot
}

# Owned SSTP: send the ghost's FMO identifier so that SSP does not ignore the request as an outside one.
$ghostId = $null
$ghostEntry = $null
if ($mode -ne 'Execute' -and -not $AnyGhost) {
    $ghostEntry = Get-DevkitSspGhost -GhostRoot $ghostRoot -SakuraName $Ghost -Port $Port
    if ($ghostEntry) { $ghostId = $ghostEntry.Id }
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
# SSP logs the places of the script that it could not interpret.
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
    Write-Host "sstp: could not connect to 127.0.0.1:$Port. Is SSP running? (start it with tools/run-ssp.ps1)"
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

$talkWait = $null
if ($watchLog -and -not $marker) {
    Write-Host 'sstp: the SSP error log cannot be read (this SSP has no developer.log properties; update SSP to see it)'
} elseif ($watchLog) {
    if ($statusAvailable -and $exitCode -eq 0) {
        # Wait for the reload and for the talk, so that every error of the script is in the log.
        if ($mode -eq 'Reload') {
            $wait = Wait-DevkitSspReload -TimeoutSeconds $TimeoutSeconds -Port $Port
        } else {
            $wait = Wait-DevkitSspTalkEnd -TimeoutSeconds $TimeoutSeconds -Port $Port
            $talkWait = $wait
        }
        if ($wait -eq 'timeout') { Write-Host "sstp: the ghost is still talking after $TimeoutSeconds seconds; reading the log anyway" }
        Start-Sleep -Milliseconds 300
    } elseif ($mode -eq 'Reload') {
        # GetStatus did not answer: the reload runs after the response. Wait until SSP answers again, then give the ghost time to boot.
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

if ($Balloon -and $response.TimedOut) {
    Write-Host 'sstp: the balloons were not written - SSP did not answer'
} elseif ($Balloon -and ($exitCode -eq 0 -or $exitCode -eq 2)) {
    $ghostPath = $null
    if ($ghostEntry) { $ghostPath = [string]$ghostEntry.Fields['ghostpath'] }
    if (-not $talkWait) {
        $talkWait = Wait-DevkitSspTalkEnd -TimeoutSeconds $TimeoutSeconds -Port $Port
        if ($talkWait -eq 'unsupported') { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ghostPath) {
        Write-Host "sstp: the balloons were not written - the folder of '$Ghost' was not found with GetFMO"
        exit 2
    }
    if ($talkWait -eq 'timeout') {
        # A new script would cut the talk (or the choice that it waits for) off.
        Write-Host 'sstp: the balloons were not written - the ghost is still talking'
        exit 2
    }

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash($DevkitUtf8.GetBytes($DevkitRoot.ToLowerInvariant()))
    } finally {
        $sha.Dispose()
    }
    $hash = -join ($bytes[0..7] | ForEach-Object { $_.ToString('x2') })
    $outDir = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'ghost-devkit') "balloons-$hash"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    Get-ChildItem -LiteralPath $outDir -Filter '*.png' -File | Remove-Item -Force

    # SSP resolves a relative folder from ghost/master of the ghost, and writes only under the folders it manages.
    $workName = 'devkit-balloon-' + [guid]::NewGuid().ToString('N')
    $work = Join-Path (Join-Path (Join-Path $ghostPath.TrimEnd('\', '/') 'ghost') 'master') $workName
    $dump = '\C'
    foreach ($scope in $BalloonScope) { $dump += '\![execute,dumpballoon,' + $workName + ',' + $scope + ']' }
    $lines = @('SEND SSTP/1.4', 'Charset: UTF-8', 'Sender: ghost-devkit', ('ReceiverGhostName: ' + $Ghost), ('ID: ' + $ghostId), ('Script: ' + $dump))
    $images = @()
    try {
        $dumpResponse = Invoke-DevkitSstp -Lines $lines -Port $Port -TimeoutSeconds $TimeoutSeconds
        if ($dumpResponse.Status -ge 200 -and $dumpResponse.Status -lt 300) {
            # SSP answers before it plays the script, so wait for the files: until every scope has one, or until
            # no new file came for a second (a scope without a balloon writes nothing), or 10 seconds in all.
            $deadline = (Get-Date).AddSeconds(10)
            $count = -1
            $stableSince = Get-Date
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 200
                if (-not (Test-Path -LiteralPath $work)) { continue }
                $now = @(Get-ChildItem -LiteralPath $work -Filter '*.png' -File).Count
                if ($now -ge $BalloonScope.Count) { break }
                if ($now -ne $count) {
                    $count = $now
                    $stableSince = Get-Date
                } elseif (((Get-Date) - $stableSince).TotalSeconds -ge 1) {
                    break
                }
            }
            # Let SSP finish writing the last file.
            Start-Sleep -Milliseconds 200
            if (Test-Path -LiteralPath $work) {
                foreach ($image in @(Get-ChildItem -LiteralPath $work -Filter '*.png' -File | Sort-Object Name)) {
                    $destination = Join-Path $outDir $image.Name
                    Move-Item -LiteralPath $image.FullName -Destination $destination -Force
                    $images += $destination
                }
            }
        } else {
            Write-Host "sstp: the balloon dump was refused: $($dumpResponse.StatusLine)"
        }
    } finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
    foreach ($image in $images) { Write-Host "balloon: $image" }
    if ($images.Count -eq 0) {
        Write-Host 'sstp: no balloon image was written (SSP 2.9.02 or later is needed for \![execute,dumpballoon])'
        if ($exitCode -eq 0) { $exitCode = 2 }
    }
}
exit $exitCode
