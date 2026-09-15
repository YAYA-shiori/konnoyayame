<#
.SYNOPSIS
    Shows the logs of a running SSP: error, script, network or update.
.DESCRIPTION
    Reads the developer.log properties with "EXECUTE GetProperty" over SSTP. Read-only.
    SSP keeps only the newest entries of each log (50 by default). Entries are printed oldest first.
    By default only the entries of this ghost are shown: SSP records the name of ghost/master/descript.txt
    (not sakura.name) as their source. Use -All to include every source, such as [SYSTEM].
      error   : dictionary errors reported by YAYA, shell (SERIKO) problems, ... (type: Info, Notice,
                Warning, Error, Critical or System). With SSP 2.8.94 or later, SERIKO entries tell the file
                and line ("shell/master/surfaces.txt:Line=123"), and tags that SSP could not interpret in
                scripts played by tools/sstp.ps1 (Option: strict) are logged as "[GHOST/Script] ...".
      script  : the scripts that were played (type: the event or SSTP request that caused it)
      network : HTTP and SSL messages (mostly [SYSTEM])
      update  : network update messages
    Exit codes: 0 = read, and no Error or Critical entry was shown, 1 = this SSP has no developer.log
    properties, 2 = an Error or Critical entry was shown, 3 = could not connect (SSP is not running).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/ssp-log.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/ssp-log.ps1 -Kind script -Max 5
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/ssp-log.ps1 -All -Json
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
    [int]$Port = 9801
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/sstp.ps1')
Initialize-DevkitConsole

if ($All) {
    $Name = $null
} elseif (-not $Name) {
    $Name = Get-DevkitDescriptValue (Join-Path $DevkitRoot 'ghost/master/descript.txt') 'name'
}

$log = Get-DevkitSspLog -Kind $Kind -Name $Name -Max $Max -Port $Port
if ($log.State -eq 'offline') {
    Write-Host "ssp-log: could not connect to 127.0.0.1:$Port. Is SSP running?"
    exit 3
}
if ($log.State -eq 'unsupported') {
    Write-Host 'ssp-log: this SSP has no developer.log properties. Update SSP.'
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
