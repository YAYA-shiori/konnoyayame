<#
.SYNOPSIS
    Runs yayalint on the ghost dictionaries (undefined / unused variables and functions).
.DESCRIPTION
    The project configuration is ghost/master/yayalint_config.lua.
    Findings in the system dictionary (dic/system or system, the yaya-dic submodule) are hidden unless
    -IncludeSystem is given.
    Chain talk labels (':chain=name') are treated as used.
    Exit codes: 0 = done (findings are advisory), 1 = undefined names found with -Strict, 3 = yayalint is not installed.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/lint.ps1
#>
[CmdletBinding()]
param(
    # Folder that contains yaya.txt (default: ghost/master).
    [string]$GhostDir,
    [switch]$IncludeSystem,
    [switch]$Strict,
    # Extra yayalint options, for example -Options '-u' (see yayalint -h).
    [string[]]$Options
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-DevkitConsole

if (-not $GhostDir) { $GhostDir = Join-Path $DevkitRoot 'ghost/master' }
$GhostDir = (Resolve-DevkitFullPath $GhostDir).TrimEnd('\', '/')
$yayaTxt = Join-Path $GhostDir 'yaya.txt'

$exe = Get-DevkitToolPath 'yayalint'
if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host 'lint: SKIPPED - yayalint is not installed. Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1'
    exit 3
}

# Chain talks are started from strings like '...\e:chain=label', which yayalint cannot follow.
$chainLabels = @{}
$dicDir = Join-Path $GhostDir 'dic'
if (Test-Path -LiteralPath $dicDir) {
    foreach ($file in Get-ChildItem -LiteralPath $dicDir -Recurse -File -Filter '*.dic') {
        $text = [IO.File]::ReadAllText($file.FullName, $DevkitUtf8)
        foreach ($m in [regex]::Matches($text, ':chain=([^''"\s\\]+)')) { $chainLabels[$m.Groups[1].Value] = $true }
    }
}

$prefix = ''
$rootWithSeparator = $DevkitRoot + [IO.Path]::DirectorySeparatorChar
if ($GhostDir.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
    $prefix = $GhostDir.Substring($rootWithSeparator.Length).Replace('\', '/') + '/'
}

$lintArgs = @()
if ($Options) { $lintArgs += $Options }
$lintArgs += $yayaTxt
$result = Invoke-DevkitProcess -FilePath $exe -Arguments $lintArgs -WorkingDirectory (Split-Path $exe -Parent) -TimeoutSeconds 300

$undefined = 0
$unused = 0
$other = 0
$hiddenSystem = 0
foreach ($line in ($result.StdOut -split "\r?\n")) {
    if ($line.Trim() -eq '') { continue }
    $fields = $line -split "`t"
    if ($fields.Count -ge 6 -and $fields[2] -eq 'at' -and $fields[4] -eq 'pos:') {
        $kind = $fields[0].TrimEnd(':')
        $name = $fields[1]
        $file = $fields[3]
        if (-not $IncludeSystem -and (Test-DevkitSystemDicPath $file)) { $hiddenSystem++; continue }
        if ($kind -eq 'unused function' -and $chainLabels.ContainsKey($name)) { continue }
        $hint = ''
        if ($fields.Count -ge 8 -and $fields[6] -like 'did you mean*' -and $fields[7]) { $hint = " (did you mean: $($fields[7]))" }
        Write-Host "$prefix$($file):$($fields[5]): $kind '$name'$hint"
        if ($kind -like '*undefined*') { $undefined++ } elseif ($kind -like '*unused*') { $unused++ } else { $other++ }
    } else {
        Write-Host (ConvertTo-DevkitRelativeText $line)
        $other++
    }
}
foreach ($line in ($result.StdErr -split "\r?\n")) {
    if ($line.Trim() -ne '') { Write-Host (ConvertTo-DevkitRelativeText $line) }
}

$summary = "undefined: $undefined, unused: $unused, other: $other"
if ($hiddenSystem -gt 0) { $summary += ", hidden in the system dictionary: $hiddenSystem (use -IncludeSystem)" }
Write-Host "lint: done ($summary)"
if ($Strict -and $undefined -gt 0) { exit 1 }
exit 0
