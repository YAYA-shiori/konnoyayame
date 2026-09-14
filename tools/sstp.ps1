<#
.SYNOPSIS
    Sends an SSTP request to a running SSP to try talks on the live ghost.
.DESCRIPTION
    By default the request is addressed to this ghost (ReceiverGhostName = sakura.name in
    ghost/master/descript.txt). Use -Ghost to address another ghost, or -AnyGhost for the active one.
    Exit codes: 0 = 2xx response, 1 = error response, 3 = could not connect (SSP is not running).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Reload ghost
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Script '\0\s[5]test\e'
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Event OnMouseDoubleClick -Reference '0,0,0,0,Head'
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/sstp.ps1 -Execute GetName
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
    [int]$Port = 9801,
    [int]$TimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-DevkitConsole

$mode = $PSCmdlet.ParameterSetName
if ($mode -eq 'Reload') { $Script = '\![reload,' + $Reload + ']' }
if ($mode -ne 'Execute' -and -not $AnyGhost -and -not $Ghost) {
    $Ghost = Get-DevkitDescriptValue (Join-Path $DevkitRoot 'ghost/master/descript.txt') 'sakura.name'
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
$request = ($headers -join "`r`n") + "`r`n`r`n"

$client = New-Object System.Net.Sockets.TcpClient
$response = $null
$timedOut = $false
try {
    try {
        $client.Connect('127.0.0.1', $Port)
    } catch {
        Write-Host "sstp: could not connect to 127.0.0.1:$Port. Is SSP running?"
        exit 3
    }
    $client.ReceiveTimeout = $TimeoutSeconds * 1000
    $stream = $client.GetStream()
    $bytes = $DevkitUtf8.GetBytes($request)
    $stream.Write($bytes, 0, $bytes.Length)
    $reader = New-Object System.IO.StreamReader($stream, $DevkitUtf8)
    try { $response = $reader.ReadToEnd() } catch { $timedOut = $true }
} finally {
    $client.Close()
}

if ($timedOut) {
    Write-Host "sstp: no response within $TimeoutSeconds seconds (the script may still be playing)"
    exit 0
}
$response = $response.TrimEnd()
Write-Host $response
$status = 0
if ($response -match '^SSTP/\d\.\d\s+(\d{3})') { $status = [int]$matches[1] }
if ($status -ge 200 -and $status -lt 300) { exit 0 }
if ($status -eq 404 -and $Ghost) {
    Write-Host "sstp: ghost '$Ghost' was not found. Is it running in SSP? Use -Ghost <sakura name> or -AnyGhost."
}
exit 1
