<#
.SYNOPSIS
    Shows the logs of a running SSP: error, script, network or update.
.DESCRIPTION
    Reads the developer.log properties with "EXECUTE GetProperty" over SSTP. Read-only.
    SSP keeps only the newest entries of each log (50 by default). Entries are printed oldest first.
    By default only the entries of this ghost are shown: SSP records the name of ghost/master/descript.txt
    (not sakura.name) as their source. Use -All to include every source, such as [SYSTEM].
      error   : dictionary errors reported by YAYA, shell (SERIKO) problems, ... (type: Info, Notice,
                Warning, Error, Critical or System). SERIKO entries tell the file
                and line ("shell/master/surfaces.txt:Line=123"), and tags that SSP could not interpret in
                scripts played by tools/sstp.ps1 (Option: strict) are logged as "[GHOST/Script] ...".
      script  : the scripts that were played (type: the event or SSTP request that caused it)
      network : HTTP and SSL messages (mostly [SYSTEM])
      update  : network update messages
    Exit codes: 0 = read, and no Error or Critical entry was shown, 1 = the log could not be read
    (SSP did not answer the developer.log properties), 2 = an Error or Critical entry was shown,
    3 = could not connect (SSP is not running).
    While the isolated SSP started by tools/run-ssp.ps1 runs, its logs are read unless -Port is given.
    -Type shows only the entries whose type contains the text (for example OnSecondChange in the script log).
    -Wait N waits up to N seconds for a new entry (one that matches -Type, if given) and prints only the new
    entries: use it to see what the ghost says by itself, such as a timer or a random talk. When nothing new
    comes, the exit code is 1.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/ssp-log.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/ssp-log.ps1 -Kind script -Max 5
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/ssp-log.ps1 -All -Json
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/ssp-log.ps1 -Kind script -Type OnSecondChange -Wait 90
#>
[CmdletBinding()]
param(
    [ValidateSet('error', 'script', 'network', 'update')]
    [string]$Kind = 'error',
    # Source name to show (default: name of ghost/master/descript.txt).
    [string]$Name,
    # Show the entries of every source.
    [switch]$All,
    # Number of the newest entries to read.
    [int]$Max = 50,
    # Print the result as JSON (for agents).
    [switch]$Json,
    # Show only the entries whose type contains this text.
    [string]$Type,
    # Wait up to this many seconds for a new entry and show only the new entries.
    [int]$Wait = 0,
    # SSTP port (default: the isolated SSP started by tools/run-ssp.ps1 while it runs, otherwise 9801).
    [int]$Port = 0
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/sstp.ps1')
Initialize-DevkitConsole
$Port = Resolve-DevkitSspPort $Port

if ($All) {
    $Name = $null
} elseif (-not $Name) {
    $Name = Get-DevkitDescriptValue (Join-Path $DevkitRoot 'ghost/master/descript.txt') 'name'
}

function Select-LogEntries([object[]]$Entries) {
    if (-not $Type) { return @($Entries) }
    return @($Entries | Where-Object { ([string]$_.type).IndexOf($Type, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
}

if ($Wait -gt 0) {
    $marker = New-DevkitSspLogMarker -Kind $Kind -Name $Name -Port $Port
    if (-not $marker) {
        $probe = Get-DevkitSspLog -Kind $Kind -Name $Name -Max 1 -Port $Port
        if ($probe.State -eq 'offline') {
            Write-Host "ssp-log: could not connect to 127.0.0.1:$Port. Is SSP running? (start it with tools/run-ssp.ps1)"
            exit 3
        }
        Write-Host 'ssp-log: the log could not be read (SSP did not answer the developer.log properties)'
        exit 1
    }
    $deadline = (Get-Date).AddSeconds($Wait)
    $log = $null
    while ($true) {
        Start-Sleep -Milliseconds 1000
        $current = Get-DevkitSspLog -Kind $Kind -Name $Name -Max $Max -Since $marker -Port $Port
        if ($current.State -ne 'ok') {
            Write-Host 'ssp-log: SSP stopped answering while waiting'
            exit 3
        }
        if (@(Select-LogEntries $current.Entries).Count -gt 0) { $log = $current; break }
        if ((Get-Date) -ge $deadline) { break }
    }
    if (-not $log) {
        $what = if ($Type) { "$Kind log entry of type '$Type'" } else { "$Kind log entry" }
        Write-Host "ssp-log: no new $what within $Wait seconds"
        exit 1
    }
} else {
    $log = Get-DevkitSspLog -Kind $Kind -Name $Name -Max $Max -Port $Port
}
$log.Entries = @(Select-LogEntries $log.Entries)
if ($log.State -eq 'offline') {
    Write-Host "ssp-log: could not connect to 127.0.0.1:$Port. Is SSP running? (start it with tools/run-ssp.ps1)"
    exit 3
}
if ($log.State -eq 'unreadable') {
    Write-Host 'ssp-log: the log could not be read (SSP did not answer the developer.log properties)'
    exit 1
}

$source = if ($Name) { "'$Name'" } else { 'all sources' }
if ($Json) {
    $entries = @($log.Entries | ForEach-Object {
        [pscustomobject]@{ index = $_.index; type = $_.type; name = $_.name; time = $_.time; value = (ConvertTo-DevkitRelativeText ([string]$_.value)) }
    })
    Write-Output ([pscustomobject]@{ kind = $Kind; name = $(if ($Name) { $Name } else { $null }); total = $log.Total; truncated = $log.Truncated; entries = $entries } | ConvertTo-Json -Depth 4)
} elseif ($log.Entries.Count -eq 0) {
    Write-Host "ssp-log: the $Kind log has no entries from $source"
} else {
    Write-DevkitSspLogEntries $log.Entries
    $summary = "ssp-log: $($log.Entries.Count) of $($log.Total) $Kind log entries from $source"
    if ($log.Truncated) { $summary += " (use -Max to read more)" }
    Write-Host $summary
}
if (Test-DevkitSspLogHasError $log.Entries) { exit 2 }
exit 0
