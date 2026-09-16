<#
.SYNOPSIS
    Looks for undefined / unused variables and functions with the lint of the system dictionary (SHIORI3FW.Lint).
.DESCRIPTION
    tamac.exe loads the ghost and evaluates SHIORI3FW.Lint.Run of yaya-dic (yaya_base/lint.dic), which reads the
    loaded dictionaries with the LINT.* functions of yaya.dll (Tc574-1 or later). SSP is not needed, and
    ghost/master/yaya_variable.cfg is put back afterwards.

    Each finding is printed as "path:line: kind 'name' in function (did you mean: ...)". The kinds are
    read undefined variable, read undefined local variable, unused function, unused variable,
    unused local variable and assignment in condition. There is no column: YAYA does not keep it.

    Names that are used only from strings are recognized when the dictionaries spell them out
    (EVAL('name'), '\e:chain=name', \q[...,name], '...%(name)...'). Functions called by a name built at run time
    (for example 'Mouse' + part) are listed as regular expressions in a function of the ghost named
    OnSHIORI3FW.Lint.UsedFunctions, and global variables in OnSHIORI3FW.Lint.UsedVariables.

    Findings in the system dictionary are hidden unless -IncludeSystem is given.
    Exit codes: 0 = done (findings are advisory), 1 = failed (load errors, no answer) or undefined names found with
    -Strict, 3 = not available (tamac.exe is missing or old, yaya.dll is older than Tc574-1, or the system dictionary
    has no yaya_base/lint.dic).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/lint.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/shiori.ps1 -Eval 'SHIORI3FW.Lint.Run'
#>
[CmdletBinding()]
param(
    # Folder that contains yaya.dll and yaya.txt (default: ghost/master).
    [string]$GhostDir,
    [switch]$IncludeSystem,
    [switch]$Strict,
    [int]$TimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-DevkitConsole

if (-not $GhostDir) { $GhostDir = Join-Path $DevkitRoot 'ghost/master' }
$GhostDir = (Resolve-DevkitFullPath $GhostDir).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath (Join-Path $GhostDir 'yaya.dll'))) {
    Write-Host "lint: FAILED - yaya.dll was not found in $GhostDir"
    exit 1
}

$tamac = Get-DevkitToolPath 'tamac'
if (-not (Test-Path -LiteralPath $tamac)) {
    Write-Host 'lint: SKIPPED - tamac.exe is not installed. Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1'
    exit 3
}
if ((Test-DevkitToolCurrent 'tamac') -eq $false) {
    Write-Host 'lint: SKIPPED - this tamac.exe is too old. Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1 -Tool tamac'
    exit 3
}

$prefix = ''
$rootWithSeparator = $DevkitRoot + [IO.Path]::DirectorySeparatorChar
if ($GhostDir.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
    $prefix = $GhostDir.Substring($rootWithSeparator.Length).Replace('\', '/') + '/'
}

$code = 'SHIORI3FW.Lint.Run'
if ($IncludeSystem) { $code = "SHIORI3FW.Lint.Run('system')" }
$requestText = '?? ' + $code
$result = Invoke-DevkitTamac -GhostDir $GhostDir -Arguments @('-r') -InputText $requestText -UnsetEnvironment @('GITHUB_ACTIONS') -TimeoutSeconds $TimeoutSeconds
if ($result.TimedOut) {
    Write-Host "lint: FAILED - tamac.exe did not finish within $TimeoutSeconds seconds"
    exit 1
}

# Errors logged before this request come from loading the dictionaries (see tools/shiori.ps1).
$base = Split-Path (Split-Path $GhostDir -Parent) -Parent
$logLines = @($result.StdErr -split "\r?\n")
$requestStart = -1
for ($i = 0; $i -lt $logLines.Count - 1; $i++) {
    if ($logLines[$i] -eq '// request' -and $logLines[$i + 1].TrimEnd() -eq $requestText) { $requestStart = $i; break }
}
$loadErrors = New-Object System.Collections.Generic.List[string]
$requestMessages = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $logLines.Count; $i++) {
    $line = $logLines[$i]
    if ($line -match '^\[(FATAL|ERROR|WARN|NOTE)\]') {
        $text = ConvertTo-DevkitRelativeText $line -Base $base
        if ($i -lt $requestStart) {
            if ($line -match '^\[(FATAL|ERROR)\]') { $loadErrors.Add($text) }
        } else {
            $requestMessages.Add($text)
        }
    }
}
if ($loadErrors.Count -gt 0) {
    foreach ($line in $loadErrors) { Write-Host $line }
    Write-Host 'lint: FAILED - the dictionaries have load errors. Fix them first (tools/check-dic.ps1).'
    exit 1
}

$response = $result.StdOut -replace "\r\n", "`n"
if (-not $response.StartsWith('!! ')) {
    if ($response.Trim() -ne '') { Write-Host $response.TrimEnd() }
    Write-Host "lint: FAILED - no answer to '$code' (tamac.exe exit code $($result.ExitCode))"
    exit 1
}
$lines = @($response.Substring(3).TrimEnd("`n") -split "`n")

$summary = $null
$undefined = 0
foreach ($line in $lines) {
    if ($line -like 'SHIORI3FW.Lint: *') {
        $summary = $line
        continue
    }
    if ($line -match '^(.+?):(\d+): (.+?) ''') {
        Write-Host "$prefix$line"
        if ($matches[3] -like '*undefined*') { $undefined++ }
    } elseif ($line.Trim() -ne '') {
        Write-Host $line
    }
}

if (-not $summary) {
    foreach ($line in $requestMessages) { Write-Host "  $line" }
    Write-Host 'lint: SKIPPED - the system dictionary has no SHIORI3FW.Lint (yaya_base/lint.dic of yaya-dic). Update it: docs/agents/workflows/update-yaya.md'
    exit 3
}
if ($summary -like 'SHIORI3FW.Lint: *not available*') {
    Write-Host ('lint: SKIPPED - ' + $summary.Substring('SHIORI3FW.Lint: '.Length) + ' Update yaya.dll: docs/agents/workflows/update-yaya.md')
    exit 3
}
if ($requestMessages.Count -gt 0) {
    Write-Host 'lint: YAYA logged messages while checking:'
    foreach ($line in $requestMessages) { Write-Host "  $line" }
}
Write-Host ('lint: ' + $summary.Substring('SHIORI3FW.Lint: '.Length))
if ($Strict -and $undefined -gt 0) { exit 1 }
exit 0
