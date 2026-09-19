# SSTP client and SSP log helpers for the development kit scripts in tools/.
# Dot-source it after lib/common.ps1: . (Join-Path $PSScriptRoot 'lib/sstp.ps1')
# Keep every tools/*.ps1 file ASCII-only and compatible with Windows PowerShell 5.1.

# SSTP port of SSP when nothing else is given.
$DevkitSspDefaultPort = 9801
# Ports looked for the isolated SSP of tools/run-ssp.ps1. 9801, 9821 and 11000 are defaults of ukagaka programs.
$DevkitSspIsolatedFirstPort = 9822
$DevkitSspIsolatedLastPort = 10999

# The isolated SSP that tools/run-ssp.ps1 started for this kit is recorded in a file under the temporary folder
# (one per kit folder), so that the ghost folder stays clean and other scripts can find its port.
function Get-DevkitSspSessionPath {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash($DevkitUtf8.GetBytes($DevkitRoot.ToLowerInvariant()))
    } finally {
        $sha.Dispose()
    }
    $hash = -join ($bytes[0..7] | ForEach-Object { $_.ToString('x2') })
    return (Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'ghost-devkit') "ssp-$hash.json")
}

function Get-DevkitProcessStartTicks([System.Diagnostics.Process]$Process) {
    try { return $Process.StartTime.ToUniversalTime().Ticks } catch { return 0 }
}

# Returns the recorded isolated SSP (port, pid, startTicks, root, sspPath) while its process is alive, or $null.
# A record whose process is gone (or whose process id was reused) is deleted.
function Get-DevkitSspSession {
    $path = Get-DevkitSspSessionPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $session = $null
    try { $session = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    $alive = $false
    if ($session) {
        try {
            $process = Get-Process -Id ([int]$session.pid) -ErrorAction Stop
            $alive = (Get-DevkitProcessStartTicks $process) -eq [long]$session.startTicks
        } catch { }
    }
    if ($alive) { return $session }
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    return $null
}

function Save-DevkitSspSession([System.Diagnostics.Process]$Process, [int]$Port, [string]$Root, [string]$SspPath) {
    $path = Get-DevkitSspSessionPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $session = [pscustomobject]@{ port = $Port; pid = $Process.Id; startTicks = (Get-DevkitProcessStartTicks $Process); root = $Root; sspPath = $SspPath }
    [IO.File]::WriteAllText($path, ($session | ConvertTo-Json), $DevkitUtf8)
}

function Remove-DevkitSspSession {
    Remove-Item -LiteralPath (Get-DevkitSspSessionPath) -Force -ErrorAction SilentlyContinue
}

# Port for the SSTP requests of a script: the -Port argument when given (greater than 0), otherwise the port of
# the isolated SSP started by tools/run-ssp.ps1 while it runs, otherwise 9801.
function Resolve-DevkitSspPort([int]$Port) {
    if ($Port -gt 0) { return $Port }
    $session = Get-DevkitSspSession
    if ($session) { return [int]$session.port }
    return $DevkitSspDefaultPort
}

# Tells whether nothing listens on a TCP port of the loopback addresses (IPv4, and IPv6 when available),
# which SSP uses for "--sstp-listen <port>".
function Test-DevkitTcpPortFree([int]$Port) {
    $addresses = @([Net.IPAddress]::Loopback)
    if ([Net.Sockets.Socket]::OSSupportsIPv6) { $addresses += [Net.IPAddress]::IPv6Loopback }
    foreach ($address in $addresses) {
        $listener = New-Object System.Net.Sockets.TcpListener($address, $Port)
        try {
            $listener.Start()
        } catch {
            return $false
        } finally {
            try { $listener.Stop() } catch { }
        }
    }
    return $true
}

# Returns the first free port for the isolated SSP, or 0 when there is none.
function Find-DevkitSspFreePort {
    for ($port = $DevkitSspIsolatedFirstPort; $port -le $DevkitSspIsolatedLastPort; $port++) {
        if (Test-DevkitTcpPortFree $port) { return $port }
    }
    return 0
}

# Sends one SSTP request to SSP on this PC. $Lines is the request without the final blank line.
# Returns Connected, TimedOut, Raw, Status (0 when unknown), StatusLine, Headers and Data (the additional data).
function Invoke-DevkitSstp {
    param(
        [string[]]$Lines,
        [int]$Port = 9801,
        [int]$TimeoutSeconds = 60
    )
    $result = [pscustomobject]@{ Connected = $false; TimedOut = $false; Raw = $null; Status = 0; StatusLine = ''; Headers = @{}; Data = '' }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        try {
            $client.Connect('127.0.0.1', $Port)
        } catch {
            return $result
        }
        $result.Connected = $true
        $client.ReceiveTimeout = $TimeoutSeconds * 1000
        $stream = $client.GetStream()
        $bytes = $DevkitUtf8.GetBytes((@($Lines) -join "`r`n") + "`r`n`r`n")
        $stream.Write($bytes, 0, $bytes.Length)
        $reader = New-Object System.IO.StreamReader($stream, $DevkitUtf8)
        try { $result.Raw = $reader.ReadToEnd() } catch { $result.TimedOut = $true }
    } finally {
        $client.Close()
    }
    if ($null -eq $result.Raw) { return $result }
    # SSP ends a response with a NUL character.
    $result.Raw = $result.Raw.TrimEnd([char]0)

    # Status line, headers, a blank line, then the additional data. Some responses have no headers at all.
    $lines = $result.Raw.Replace("`r`n", "`n").Split("`n")
    $result.StatusLine = $lines[0]
    if ($result.StatusLine -match '^SSTP/\d\.\d\s+(\d{3})') { $result.Status = [int]$matches[1] }
    $i = 1
    while ($i -lt $lines.Count -and $lines[$i] -match '^([A-Za-z][A-Za-z0-9.\-]*): ?(.*)$') {
        $result.Headers[$matches[1]] = $matches[2]
        $i++
    }
    if ($i -lt $lines.Count -and $lines[$i] -eq '') { $i++ }
    if ($i -lt $lines.Count) { $result.Data = ($lines[$i..($lines.Count - 1)] -join "`n").TrimEnd("`n") }
    return $result
}

# Finds the FMO identifier of a running ghost with "EXECUTE GetFMO" (SSP only). Sending it in the ID header
# makes an "Owned SSTP" request, which SSP handles like the ghost's own processing. Without it, SSP applies
# the security limits for other programs and silently ignores things such as \![reload,ghost].
# The ghost is matched by ghostpath (GhostRoot) first, then by name (SakuraName). Returns $null when not found.
function Get-DevkitSspGhostId([string]$GhostRoot, [string]$SakuraName, [int]$Port = 9801) {
    $response = Invoke-DevkitSstp -Lines @('EXECUTE SSTP/1.1', 'Charset: UTF-8', 'Sender: ghost-devkit', 'Command: GetFMO') -Port $Port -TimeoutSeconds 10
    if ($response.Status -ne 200) { return $null }
    # Each line is "<32-byte identifier>.<key><byte 1><value>".
    $ghosts = [ordered]@{}
    foreach ($line in $response.Data.Split("`n")) {
        $dot = $line.IndexOf('.')
        $separator = $line.IndexOf([char]1)
        if ($dot -le 0 -or $separator -le $dot) { continue }
        $id = $line.Substring(0, $dot)
        if (-not $ghosts.Contains($id)) { $ghosts[$id] = @{} }
        $ghosts[$id][$line.Substring($dot + 1, $separator - $dot - 1)] = $line.Substring($separator + 1).TrimEnd("`r")
    }
    if ($GhostRoot) {
        $root = $GhostRoot.TrimEnd('\', '/')
        foreach ($id in $ghosts.Keys) {
            $path = [string]$ghosts[$id]['ghostpath']
            if ($path -and $path.TrimEnd('\', '/') -ieq $root) { return $id }
        }
    }
    if ($SakuraName) {
        foreach ($id in $ghosts.Keys) {
            if ($ghosts[$id]['name'] -ceq $SakuraName) { return $id }
        }
    }
    return $null
}

# Reads the state of the running ghost with "EXECUTE GetStatus". States are the same as the
# SHIORI/3.0 Status header, for example talking, choosing, online, opening(input) or balloon(0=0).
# Returns an object whose States is the list (empty when no state applies), or $null when SSP did not answer 200:
# SSP is not running, or the ghost is being loaded (SSP answers 400 meanwhile).
function Get-DevkitSspStatus([int]$Port = 9801) {
    $response = Invoke-DevkitSstp -Lines @('EXECUTE SSTP/1.1', 'Charset: UTF-8', 'Sender: ghost-devkit', 'Command: GetStatus') -Port $Port -TimeoutSeconds 5
    if ($response.Status -ne 200) { return $null }
    return [pscustomobject]@{ States = @($response.Data.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
}

# Waits until the ghost has finished talking, with GetStatus. SSP answers SEND and NOTIFY before it plays the
# script, and it logs script errors (Option: strict) while playing, so the error log is complete only afterwards.
# Waits up to StartSeconds for the talk to start (a script with nothing to play never shows "talking"), then up
# to TimeoutSeconds in all. Returns done, timeout (still talking, for example waiting for a click) or unsupported
# (GetStatus did not answer; the caller should fall back to a fixed wait).
function Wait-DevkitSspTalkEnd([double]$StartSeconds = 1, [int]$TimeoutSeconds = 60, [int]$Port = 9801) {
    $start = Get-Date
    $talked = $false
    while ($true) {
        $status = Get-DevkitSspStatus $Port
        if ($null -eq $status) {
            if ($talked) { return 'done' }
            return 'unsupported'
        }
        $elapsed = ((Get-Date) - $start).TotalSeconds
        if ($status.States -contains 'talking') {
            $talked = $true
        } elseif ($talked -or $elapsed -ge $StartSeconds) {
            return 'done'
        }
        if ($elapsed -ge $TimeoutSeconds) { return 'timeout' }
        Start-Sleep -Milliseconds 200
    }
}

# Waits for a ghost reload that was just requested, then for the talk after it. While the ghost is being loaded,
# GetStatus does not answer 200. The reload itself starts after the \![reload,...] script is played, and a
# quick reload can pass between two polls, so this stops waiting for it after GraceSeconds of not talking.
# Call it only when GetStatus answered before the request; otherwise it waits for TimeoutSeconds.
# Returns the same values as Wait-DevkitSspTalkEnd.
function Wait-DevkitSspReload([double]$GraceSeconds = 2, [int]$TimeoutSeconds = 30, [int]$Port = 9801) {
    $start = Get-Date
    $reloading = $false
    $graceStart = $start
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
        $status = Get-DevkitSspStatus $Port
        if ($null -eq $status) {
            $reloading = $true
        } elseif ($status.States -contains 'talking') {
            $graceStart = Get-Date
        } elseif ($reloading -or ((Get-Date) - $graceStart).TotalSeconds -ge $GraceSeconds) {
            break
        }
        Start-Sleep -Milliseconds 200
    }
    return (Wait-DevkitSspTalkEnd -StartSeconds 1 -TimeoutSeconds $TimeoutSeconds -Port $Port)
}

# Reads a property system value with "EXECUTE GetProperty" and returns the SSTP response.
function Get-DevkitSspProperty([string]$Name, [int]$Port = 9801) {
    return Invoke-DevkitSstp -Lines @('EXECUTE SSTP/1.1', 'Charset: UTF-8', 'Sender: ghost-devkit', 'Command: GetProperty', ('Reference0: ' + $Name)) -Port $Port -TimeoutSeconds 10
}

function Get-DevkitSspLogKey([object]$Entry) {
    return ($Entry.type, $Entry.name, $Entry.time, $Entry.value) -join "`n"
}

# Reads the newest entries of an SSP log (developer.log.<Kind>; SSP keeps about 50 of each).
# Kind: script, error, network or update. Name: only entries whose source (a ghost name, [SYSTEM], ...) matches.
# Since: a marker from New-DevkitSspLogMarker; only the entries added after the marker are returned.
# Returns State (ok / offline / unsupported), Total, Entries (newest first: index, type, name, time, value),
# Truncated (more entries than Max) and MarkerLost (the marked entry is gone, so older entries may be included).
function Get-DevkitSspLog {
    param(
        [string]$Kind = 'error',
        [string]$Name,
        [int]$Max = 50,
        [object]$Since,
        [int]$Port = 9801
    )
    $base = 'developer.log.' + $Kind
    if ($Name) { $base += '(' + $Name + ')' }
    $log = [pscustomobject]@{ State = 'ok'; Total = 0; Entries = @(); Truncated = $false; MarkerLost = $false }

    $response = Get-DevkitSspProperty ($base + '.count') $Port
    if (-not $response.Connected) {
        $log.State = 'offline'
        return $log
    }
    if ($response.Status -lt 200 -or $response.Status -ge 300 -or $response.Data.Trim() -notmatch '^\d+$') {
        $log.State = 'unsupported'
        return $log
    }
    $log.Total = [int]$response.Data.Trim()

    # Entries are numbered from the newest one, so the marked entry moves down as new entries arrive.
    # When the count grew, at least that many entries are new even if they look the same as the marked one.
    $minNew = 0
    if ($Since) { $minNew = [Math]::Max(0, $log.Total - $Since.Total) }
    $entries = New-Object System.Collections.Generic.List[object]
    $markerFound = $false
    for ($i = 0; $i -lt $log.Total; $i++) {
        if ($entries.Count -ge $Max) {
            $log.Truncated = $true
            break
        }
        $entry = [ordered]@{ index = $i }
        foreach ($property in @('type', 'name', 'time', 'value')) {
            $r = Get-DevkitSspProperty "$base.index($i).$property" $Port
            if ($r.Status -lt 200 -or $r.Status -ge 300) {
                $entry = $null
                break
            }
            $entry[$property] = $r.Data
        }
        if ($null -eq $entry) { break }
        $entry = [pscustomobject]$entry
        if ($Since -and $Since.Key -and $i -ge $minNew -and (Get-DevkitSspLogKey $entry) -eq $Since.Key) {
            $markerFound = $true
            break
        }
        $entries.Add($entry)
    }
    if ($Since -and $Since.Key -and -not $markerFound -and -not $log.Truncated) { $log.MarkerLost = $true }
    $log.Entries = $entries.ToArray()
    return $log
}

# Remembers the newest entry of an SSP log, to read only the entries added later (Get-DevkitSspLog -Since).
# Returns $null when the log cannot be read (SSP is not running, or it does not support developer.log).
function New-DevkitSspLogMarker([string]$Kind = 'error', [string]$Name, [int]$Port = 9801) {
    $log = Get-DevkitSspLog -Kind $Kind -Name $Name -Max 1 -Port $Port
    if ($log.State -ne 'ok') { return $null }
    $key = ''
    if ($log.Entries.Count -gt 0) { $key = Get-DevkitSspLogKey $log.Entries[0] }
    return [pscustomobject]@{ Kind = $Kind; Name = $Name; Total = $log.Total; Key = $key }
}

function Test-DevkitSspLogHasError([object[]]$Entries) {
    return (@($Entries | Where-Object { $_.type -match '^(Error|Critical)$' }).Count -gt 0)
}

# Prints the entries added since a request, leaving out Info and Notice entries (for example unused
# surfaces, which check-shell also reports). Returns $true when an Error or Critical entry was printed.
function Write-DevkitSspLogSummary([string]$Prefix, [object]$Log, [int]$Max, [string]$Base = $DevkitRoot) {
    if ($Log.State -ne 'ok') {
        Write-Host "${Prefix}: the SSP error log could not be read"
        return $false
    }
    $shown = @($Log.Entries | Where-Object { $_.type -notmatch '^(Info|Notice)$' })
    $hidden = $Log.Entries.Count - $shown.Count
    $note = ''
    if ($hidden -gt 0) { $note = " ($hidden Info/Notice entries not shown; see tools/ssp-log.ps1)" }
    if ($shown.Count -eq 0) {
        Write-Host "${Prefix}: no new warnings or errors in the SSP error log$note"
        return $false
    }
    Write-Host "${Prefix}: new entries in the SSP error log$note"
    Write-DevkitSspLogEntries $shown -Base $Base
    if ($Log.Truncated) { Write-Host "${Prefix}: only the newest $Max entries were read. Run tools/ssp-log.ps1 -All for more." }
    if ($Log.MarkerLost) { Write-Host "${Prefix}: the log was trimmed or summarized meanwhile, so some of these entries may be older" }
    return (Test-DevkitSspLogHasError $shown)
}

# Prints log entries oldest first. Paths under $Base are shortened to relative paths.
function Write-DevkitSspLogEntries([object[]]$Entries, [string]$Base = $DevkitRoot) {
    for ($i = $Entries.Count - 1; $i -ge 0; $i--) {
        $entry = $Entries[$i]
        $value = ConvertTo-DevkitRelativeText ([string]$entry.value) -Base $Base
        Write-Host ('[{0}] {1} {2}: {3}' -f $entry.type, $entry.time, $entry.name, $value)
    }
}
