<#
.SYNOPSIS
    Checks the development environment and tells what is missing and how to get it.
.DESCRIPTION
    Read-only: nothing is installed or changed.
    Each item has a level: required (the checks cannot run without it), recommended, or optional.
    Exit codes: 0 = all required items are ready, 1 = a required item is missing.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/doctor.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/doctor.ps1 -Json
#>
[CmdletBinding()]
param(
    # Print the result as JSON (for agents).
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-DevkitConsole

$items = New-Object System.Collections.Generic.List[object]
function Add-DoctorItem {
    param([string]$Id, [string]$Name, [string]$Level, [bool]$Ok, [string]$Purpose, [string]$Detail, [string]$Fix)
    $items.Add([pscustomobject]@{ id = $Id; name = $Name; level = $Level; ok = $Ok; purpose = $Purpose; detail = $Detail; fix = $Fix })
}

$ps = 'powershell -NoProfile -ExecutionPolicy Bypass -File'
$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
$isGitWorkingCopy = Test-Path -LiteralPath (Join-Path $DevkitRoot '.git')

# --- Windows ---------------------------------------------------------------------------
$isWindowsOs = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
Add-DoctorItem -Id 'windows' -Name 'Windows' -Level 'required' -Ok $isWindowsOs `
    -Purpose 'SSP, YAYA and tamac.exe run only on Windows' `
    -Detail ([Environment]::OSVersion.VersionString) `
    -Fix 'Use a Windows PC.'

# --- Windows PowerShell (used by tools/*.ps1 and the Claude Code hooks) ------------------
$windowsPowerShell = Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
Add-DoctorItem -Id 'powershell' -Name 'Windows PowerShell' -Level 'required' -Ok ([bool]$windowsPowerShell) `
    -Purpose 'Runs tools/*.ps1 and the Claude Code hooks' `
    -Detail $(if ($windowsPowerShell) { "PowerShell $($PSVersionTable.PSVersion) is running; powershell.exe found" } else { 'powershell.exe was not found' }) `
    -Fix 'Windows PowerShell is part of Windows. Check that it has not been removed or blocked.'

# --- ghost files -----------------------------------------------------------------------
$dll = Join-Path $DevkitRoot 'ghost/master/yaya.dll'
$ghostOk = (Test-Path -LiteralPath $dll) -and (Test-Path -LiteralPath (Join-Path $DevkitRoot 'ghost/master/yaya.txt'))
Add-DoctorItem -Id 'ghost' -Name 'ghost files' -Level 'required' -Ok $ghostOk `
    -Purpose 'The ghost itself' `
    -Detail $(if ($ghostOk) { "yaya.dll $((Get-Item -LiteralPath $dll).VersionInfo.FileVersion)" } else { 'ghost/master/yaya.dll or ghost/master/yaya.txt is missing' }) `
    -Fix 'Work in the ghost root folder (the one that contains ghost/ and shell/).'

$systemOk = Test-Path -LiteralPath (Join-Path $DevkitRoot 'ghost/master/dic/system/yaya_base/shiori3.dic')
Add-DoctorItem -Id 'system-dic' -Name 'system dictionary (ghost/master/dic/system)' -Level 'required' -Ok $systemOk `
    -Purpose 'YAYA system dictionary (yaya-dic)' `
    -Detail $(if ($systemOk) { 'present' } else { 'empty' }) `
    -Fix $(if ($isGitWorkingCopy) { "Run: $ps tools/setup.ps1 (it runs git submodule update --init)" } else { 'The folder is incomplete. Download the nar again from the Releases page.' })

# --- downloaded tools ------------------------------------------------------------------
$manifest = Get-DevkitToolManifest
$tamacPath = Get-DevkitToolPath 'tamac'
Add-DoctorItem -Id 'tamac' -Name 'tamac.exe' -Level 'required' -Ok (Test-Path -LiteralPath $tamacPath) `
    -Purpose 'Dictionary check (tools/check-dic.ps1 and the check after each edit)' `
    -Detail $(if (Test-Path -LiteralPath $tamacPath) { "$($manifest.tamac.version) in tools/bin" } else { 'not installed' }) `
    -Fix "Run: $ps tools/setup.ps1"

$yayalintPath = Get-DevkitToolPath 'yayalint'
Add-DoctorItem -Id 'yayalint' -Name 'yayalint' -Level 'optional' -Ok (Test-Path -LiteralPath $yayalintPath) `
    -Purpose 'Static analysis of dictionaries (tools/lint.ps1)' `
    -Detail $(if (Test-Path -LiteralPath $yayalintPath) { "$($manifest.yayalint.version) in tools/bin" } else { 'not installed' }) `
    -Fix "Run: $ps tools/setup.ps1"

# --- SSP -------------------------------------------------------------------------------
$ssp = Resolve-SspPath
$sspDetail = if ($ssp) { "$($ssp.Path) (found via $($ssp.Source))" } else { 'not found' }
$local = Get-DevkitLocalConfig
if (-not $ssp -and ($env:SSP_PATH -or ($local -and ($local.PSObject.Properties.Name -contains 'sspPath')))) {
    $sspDetail = 'not found; the path in SSP_PATH or tools/local.json does not exist'
}
Add-DoctorItem -Id 'ssp' -Name 'SSP' -Level 'recommended' -Ok ([bool]$ssp) `
    -Purpose 'Shell check (tools/check-shell.ps1), running the ghost (tools/run-ssp.ps1), trying talks (tools/sstp.ps1) and reading its logs (tools/ssp-log.ps1)' `
    -Detail $sspDetail `
    -Fix 'Get SSP from https://ssp.shillest.net/ . If it is already installed, ask where ssp.exe is and write it to tools/local.json as {"sspPath": "C:\\path\\to\\ssp.exe"}.'

# --- git -------------------------------------------------------------------------------
$git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$gitDetail = 'not found'
if ($git) { $gitDetail = (Invoke-DevkitProcess -FilePath $git.Source -Arguments @('--version') -TimeoutSeconds 30).StdOut.Trim() }
Add-DoctorItem -Id 'git' -Name 'Git' -Level 'recommended' -Ok ([bool]$git) `
    -Purpose 'Version history, GitHub (checks and automatic releases), and the dic/system submodule in a git clone' `
    -Detail $gitDetail `
    -Fix $(if ($hasWinget) { 'After the user agrees, run: winget install --id Git.Git -e (then restart the terminal)' } else { 'Download from https://git-scm.com/download/win' })

# --- Node.js ---------------------------------------------------------------------------
$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$nodeOk = $false
$nodeDetail = 'not found'
if ($node) {
    $nodeDetail = (Invoke-DevkitProcess -FilePath $node.Source -Arguments @('--version') -TimeoutSeconds 30).StdOut.Trim()
    $nodeOk = ($nodeDetail -match '^v(\d+)\.') -and ([int]$matches[1] -ge 20)
    if (-not $nodeOk) { $nodeDetail += ' (version 20 or later is needed)' }
}
Add-DoctorItem -Id 'node' -Name 'Node.js 20+' -Level 'optional' -Ok $nodeOk `
    -Purpose 'ukagaka-doc MCP server (offline search of UKADOC and YAYA Wiki)' `
    -Detail $nodeDetail `
    -Fix $(if ($hasWinget) { 'After the user agrees, run: winget install --id OpenJS.NodeJS.LTS -e (then restart the terminal)' } else { 'Download the LTS version from https://nodejs.org/' })

# --- output ----------------------------------------------------------------------------
$missingRequired = @($items | Where-Object { $_.level -eq 'required' -and -not $_.ok })
$ready = $missingRequired.Count -eq 0
if ($Json) {
    Write-Output ([pscustomobject]@{ ready = $ready; root = $DevkitRoot; gitWorkingCopy = $isGitWorkingCopy; winget = $hasWinget; items = $items.ToArray() } | ConvertTo-Json -Depth 4)
} else {
    foreach ($item in $items) {
        $mark = if ($item.ok) { '[ok]     ' } elseif ($item.level -eq 'required') { '[MISSING]' } else { '[missing]' }
        Write-Host ('{0} {1} ({2}): {3}' -f $mark, $item.name, $item.level, $item.detail)
        if (-not $item.ok) {
            Write-Host "          purpose: $($item.purpose)"
            Write-Host "          fix    : $($item.fix)"
        }
    }
    if ($ready) {
        Write-Host 'doctor: all required items are ready'
    } else {
        Write-Host "doctor: missing required item(s): $(($missingRequired | ForEach-Object { $_.name }) -join ', ')"
    }
}
if ($ready) { exit 0 }
exit 1
