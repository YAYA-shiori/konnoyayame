<#
.SYNOPSIS
    Sends one SHIORI request to the ghost's yaya.dll with tamac.exe, without SSP.
.DESCRIPTION
    tamac.exe loads the dictionaries, sends the request, prints the response and unloads YAYA (tamac -r).
    SSP does not need to be running, and nothing appears on the desktop.

    -Eval evaluates YAYA code through the system dictionary (yaya-dic answers "?? code" with "!! result").
    Give a function name to see what it returns (a talk, for example), or a built-in function to see how it
    behaves with this yaya.dll. Array results are joined with commas. Several lines are evaluated one by one
    and their results are joined; local variables (_name) do not carry over to the next line.

    -Event sends "GET SHIORI/3.0" (NOTIFY with -Notify) with ID and References, as SSP does for an event or a
    resource. Sender is SSP, SecurityLevel is local, and Charset is charset.output of ghost/master/yaya.txt
    (the system dictionary switches its output charset to the Charset header). -Header adds or replaces headers.

    -Request sends the given text as it is. tamac.exe turns the line breaks into CRLF and adds the blank line.

    Each call loads the ghost from scratch: no OnBoot or other event is sent before the request, and global
    variables are the ones saved in ghost/master/yaya_variable.cfg. The file is put back afterwards, so nothing
    that the request changes is kept. The code runs in the real dictionaries, though: code that writes files,
    runs programs or calls SAORI really does so.

    Errors that YAYA logs are shown after the response (warnings and notes too with -Level).
    Exit codes: 0 = OK, 1 = failed (yaya.dll could not be loaded, the dictionaries have load errors, no or an
    error response, or -Eval was not answered by the system dictionary), 2 = YAYA logged an error while handling
    the request (the response may be incomplete), 3 = tamac.exe is not installed or has no -r option.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/shiori.ps1 -Eval 'OnBoot'
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/shiori.ps1 -Eval "SPLIT('a,b', ',')"
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/shiori.ps1 -Event OnMouseDoubleClick -Reference '0,0,0,0,Head'
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/shiori.ps1 -Event version
#>
[CmdletBinding(DefaultParameterSetName = 'Eval')]
param(
    # YAYA code to evaluate (sent as "?? code").
    [Parameter(ParameterSetName = 'Eval', Mandatory = $true, Position = 0)]
    [string]$Eval,

    # SHIORI event or resource ID.
    [Parameter(ParameterSetName = 'Event', Mandatory = $true)]
    [Alias('Event')]
    [string]$EventName,

    # Event references. Commas separate Reference0, Reference1, ...
    [Parameter(ParameterSetName = 'Event')]
    [string[]]$Reference,

    # Send NOTIFY instead of GET.
    [Parameter(ParameterSetName = 'Event')]
    [switch]$Notify,

    # Headers to add or replace, as 'Name: value'.
    [Parameter(ParameterSetName = 'Event')]
    [string[]]$Header,

    # Raw SHIORI request: the request line and the headers.
    [Parameter(ParameterSetName = 'Request', Mandatory = $true)]
    [string]$Request,

    # Folder that contains yaya.dll (default: ghost/master).
    [string]$GhostDir,
    # Lowest level of the YAYA messages to show (tamac -l; default: error).
    [ValidateSet('fatal', 'error', 'warning', 'note')]
    [string]$Level,
    # Also print the whole YAYA log (load, request and unload).
    [switch]$ShowLog,
    [int]$TimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-DevkitConsole

if (-not $GhostDir) { $GhostDir = Join-Path $DevkitRoot 'ghost/master' }
$GhostDir = (Resolve-DevkitFullPath $GhostDir).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath (Join-Path $GhostDir 'yaya.dll'))) {
    Write-Host "shiori: FAILED - yaya.dll was not found in $GhostDir"
    exit 1
}

$tamac = Get-DevkitToolPath 'tamac'
if (-not (Test-Path -LiteralPath $tamac)) {
    Write-Host 'shiori: SKIPPED - tamac.exe is not installed. Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1'
    exit 3
}
# An older tamac.exe than minimumVersion in tools/tools.json may not have -r (added in v1.0.3.25); it would ignore it.
if ((Test-DevkitToolCurrent 'tamac') -eq $false) {
    Write-Host 'shiori: SKIPPED - this tamac.exe is too old. Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1 -Tool tamac'
    exit 3
}

# Reads "key, value // comment" from a YAYA configuration file.
function Get-YayaSetting([string]$Path, [string]$Key) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in [IO.File]::ReadAllLines($Path, $DevkitUtf8)) {
        $text = $line -replace '//.*$', ''
        $idx = $text.IndexOf(',')
        if ($idx -gt 0 -and $text.Substring(0, $idx).Trim() -eq $Key) { return $text.Substring($idx + 1).Trim() }
    }
    return $null
}

$mode = $PSCmdlet.ParameterSetName
switch ($mode) {
    'Eval' {
        if ($Eval.Trim() -eq '') {
            Write-Host 'shiori: -Eval is empty'
            exit 1
        }
        $requestText = '?? ' + $Eval
    }
    'Event' {
        $headers = New-Object System.Collections.Generic.List[string]
        if ($Notify) { $headers.Add('NOTIFY SHIORI/3.0') } else { $headers.Add('GET SHIORI/3.0') }
        # The system dictionary sets charset.output to the Charset header, so send the ghost's own charset.
        $yayaTxt = Join-Path $GhostDir 'yaya.txt'
        $charset = Get-YayaSetting $yayaTxt 'charset.output'
        if (-not $charset) { $charset = Get-YayaSetting $yayaTxt 'charset' }
        if ($charset -and $charset -notmatch '^(?i:default|osnative)$') { $headers.Add('Charset: ' + $charset) }
        $headers.Add('Sender: SSP')
        $headers.Add('SecurityLevel: local')
        $headers.Add('ID: ' + $EventName)
        $references = @($Reference | Where-Object { $null -ne $_ } | ForEach-Object { $_ -split ',' })
        for ($i = 0; $i -lt $references.Count; $i++) { $headers.Add("Reference${i}: " + $references[$i]) }
        foreach ($extra in @($Header | Where-Object { $_ })) {
            if ($extra -notmatch '^([^:\s]+):') {
                Write-Host "shiori: -Header must be 'Name: value': $extra"
                exit 1
            }
            $prefix = $matches[1] + ':'
            $index = -1
            for ($i = 1; $i -lt $headers.Count; $i++) {
                if ($headers[$i].StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $index = $i; break }
            }
            if ($index -ge 0) { $headers[$index] = $extra } else { $headers.Add($extra) }
        }
        foreach ($line in $headers) {
            if ($line -match "[\r\n]") {
                Write-Host 'shiori: values must be a single line'
                exit 1
            }
        }
        $requestText = $headers -join "`n"
    }
    'Request' {
        $requestText = $Request
        if ($requestText.Trim() -eq '') {
            Write-Host 'shiori: -Request is empty'
            exit 1
        }
    }
}
$firstLine = ($requestText -split "\r\n|\r|\n")[0].TrimEnd()

$tamacArgs = @('-r')
if ($Level) { $tamacArgs += @('-l', $Level) }
# On GitHub Actions tamac.exe switches to its --ci output by itself; keep the plain output that is read below.
$result = Invoke-DevkitTamac -GhostDir $GhostDir -Arguments $tamacArgs -InputText $requestText -UnsetEnvironment @('GITHUB_ACTIONS') -TimeoutSeconds $TimeoutSeconds

# Paths in the output are shown relative to the ghost root (the folder with ghost/ and shell/).
$base = Split-Path (Split-Path $GhostDir -Parent) -Parent

# YAYA logs each call as "// request" and its text: loading the ghost, this request, then unloading.
# Messages before this request come from loading the dictionaries.
$logLines = @($result.StdErr -split "\r?\n")
$requestStart = -1
for ($i = 0; $i -lt $logLines.Count - 1; $i++) {
    if ($logLines[$i] -eq '// request' -and $logLines[$i + 1].TrimEnd() -eq $firstLine) { $requestStart = $i; break }
}
$loadMessages = New-Object System.Collections.Generic.List[string]
$requestMessages = New-Object System.Collections.Generic.List[string]
$loadErrors = 0
for ($i = 0; $i -lt $logLines.Count; $i++) {
    $line = $logLines[$i]
    if ($line -match '^\[(FATAL|ERROR|WARN|NOTE)\]') {
        $text = ConvertTo-DevkitRelativeText $line -Base $base
        if ($i -lt $requestStart) {
            $loadMessages.Add($text)
            if ($line -match '^\[(FATAL|ERROR)\]') { $loadErrors++ }
        } else {
            $requestMessages.Add($text)
        }
    } elseif ($line -match '^\[tamac\]') {
        $requestMessages.Add($line)
    }
}

$response = $result.StdOut -replace "\r\n", "`n"
$exitCode = 0
$failure = $null
if ($mode -eq 'Eval') {
    if ($response.StartsWith('!! ')) {
        Write-Host $response.Substring(3).TrimEnd("`n")
    } else {
        if ($response.Trim() -ne '') { Write-Host $response.TrimEnd() }
        $failure = "-Eval was not answered with '!! result'. It needs the system dictionary (yaya-dic) and dictionaries without load errors"
    }
} elseif ($response.Trim() -ne '') {
    Write-Host $response.TrimEnd()
    if ($response -match '^SHIORI/\d\.\d\s+(\d{3})' -and [int]$matches[1] -ge 400) {
        $failure = "error response ($($response.Split("`n")[0].Trim()))"
    }
}

if ($ShowLog) {
    Write-Host '---- YAYA log ----'
    foreach ($line in $logLines) { Write-Host (ConvertTo-DevkitRelativeText $line -Base $base) }
    Write-Host '------------------'
}
if ($loadMessages.Count -gt 0) {
    Write-Host 'shiori: messages while loading the dictionaries:'
    foreach ($line in $loadMessages) { Write-Host "  $line" }
}
if ($requestMessages.Count -gt 0) {
    Write-Host 'shiori: messages while handling the request:'
    foreach ($line in $requestMessages) { Write-Host "  $line" }
}

if ($result.TimedOut) {
    Write-Host "shiori: FAILED - tamac.exe did not finish within $TimeoutSeconds seconds"
    exit 1
}
if ($loadErrors -gt 0) {
    Write-Host 'shiori: FAILED - the dictionaries have load errors, so YAYA answered in emergency mode. Fix them first (tools/check-dic.ps1).'
    exit 1
}
if ($result.ExitCode -ne 0 -and $result.ExitCode -ne 2) {
    Write-Host "shiori: FAILED (tamac.exe exit code $($result.ExitCode))"
    exit 1
}
if ($failure) {
    Write-Host "shiori: FAILED - $failure"
    exit 1
}
if ($result.ExitCode -eq 2 -or $requestMessages.Count -gt 0) {
    if ($mode -eq 'Eval') {
        Write-Host 'shiori: YAYA logged messages while evaluating (see above). When EVAL fails, the result is the code itself.'
    } else {
        Write-Host 'shiori: YAYA logged messages while handling the request (see above).'
    }
    $exitCode = 2
}
exit $exitCode
