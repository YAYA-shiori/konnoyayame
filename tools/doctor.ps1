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
. (Join-Path $PSScriptRoot 'lib/devkit.ps1')
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

$systemDir = Get-DevkitSystemDicDir
$systemOk = [bool]$systemDir
$systemDetail = 'no .dic files in ' + (($DevkitSystemDicDirs | ForEach-Object { "ghost/master/$_" }) -join ' or ')
if ($systemDir) {
    $systemDetail = "ghost/master/$systemDir"
    if (-not (Test-DevkitYayaDicLayout (Join-Path (Join-Path $DevkitRoot 'ghost/master') $systemDir))) {
        $systemDetail += ' (an older layout than yaya-dic; tools/update-yaya.ps1 cannot update it until it is reorganized as in docs/agents/workflows/update-yaya.md)'
    }
} else {
    # Older ghosts may keep the system dictionary elsewhere, such as directly in ghost/master. The ghost still works.
    $oldSystemDic = @(Find-DevkitOldSystemDicFiles | Where-Object { $_ -match '(^|/)yaya_shiori3\.dic$' })
    if ($oldSystemDic.Count -gt 0) {
        $systemOk = $true
        $systemDetail = "an older layout: $($oldSystemDic -join ', ') (tools/update-yaya.ps1 cannot update it until it is reorganized as in docs/agents/workflows/update-yaya.md)"
    }
}
Add-DoctorItem -Id 'system-dic' -Name 'system dictionary' -Level 'required' -Ok $systemOk `
    -Purpose 'YAYA system dictionary (yaya-dic)' `
    -Detail $systemDetail `
    -Fix $(if ($isGitWorkingCopy) { "Run: $ps tools/setup.ps1 (it runs git submodule update --init)" } else { 'The folder is incomplete. Download the nar again from the Releases page.' })

# --- ghost profile and kit updates -----------------------------------------------------
$ghostProfile = Join-Path $DevkitRoot 'GHOST.md'
$profileState = 'ok'
if (-not (Test-Path -LiteralPath $ghostProfile -PathType Leaf)) {
    $profileState = 'missing'
} elseif ([IO.File]::ReadAllText($ghostProfile, $DevkitUtf8).Contains($DevkitGhostTemplateMarker)) {
    $profileState = 'template'
}
Add-DoctorItem -Id 'ghost-profile' -Name 'GHOST.md' -Level 'recommended' -Ok ($profileState -eq 'ok') `
    -Purpose 'Ghost-specific notes that agents read before working: characters, surfaces, license, dictionary files' `
    -Detail $(if ($profileState -eq 'ok') { 'filled in' } elseif ($profileState -eq 'template') { 'still the blank template' } else { 'missing' }) `
    -Fix $(if ($profileState -eq 'missing') { 'Copy tools/devkit/seed/GHOST.md to GHOST.md and fill it in from the dictionaries and the shell (docs/agents/workflows/setup.md).' } else { 'Fill it in from the dictionaries and the shell, confirm it with the author, then remove the devkit:ghost-template marker lines (docs/agents/workflows/setup.md).' })

$conflicts = @(Get-DevkitConflictFiles $DevkitRoot)
Add-DoctorItem -Id 'devkit-conflicts' -Name 'development kit merges' -Level 'recommended' -Ok ($conflicts.Count -eq 0) `
    -Purpose 'Kit files changed both locally and upstream by tools/update-devkit.ps1' `
    -Detail $(if ($conflicts.Count -eq 0) { 'nothing to merge' } else { 'waiting to be merged: ' + ($conflicts -join ', ') }) `
    -Fix $('Merge each <file>.devkit-new into <file>, then delete the .devkit-new file (docs/agents/workflows/update-devkit.md).' + $(if ($conflicts -contains 'AGENTS.md.devkit-new') { ' Start with AGENTS.md.devkit-new.' } else { '' }))

# --- downloaded tools ------------------------------------------------------------------
$manifest = Get-DevkitToolManifest
$tamacPath = Get-DevkitToolPath 'tamac'
$tamacCurrent = Test-DevkitToolCurrent 'tamac'
$tamacVersion = if ($null -ne $tamacCurrent) { Get-DevkitFileVersion $tamacPath } else { $null }
Add-DoctorItem -Id 'tamac' -Name 'tamac.exe' -Level 'required' -Ok ($null -ne $tamacCurrent) `
    -Purpose 'Dictionary check (tools/check-dic.ps1 and the check after each edit)' `
    -Detail $(if ($null -eq $tamacCurrent) { 'not installed' } elseif ($tamacVersion) { "v$tamacVersion in tools/bin" } else { 'in tools/bin (version unknown)' }) `
    -Fix "Run: $ps tools/setup.ps1"

# An older tamac.exe still checks the dictionaries, so being out of date is only recommended.
$tamacMinimum = $manifest.tamac.minimumVersion
Add-DoctorItem -Id 'tamac-version' -Name "tamac.exe $tamacMinimum or later" -Level 'recommended' -Ok ($tamacCurrent -ne $false) `
    -Purpose 'SHIORI requests without SSP (tools/shiori.ps1)' `
    -Detail $(if ($null -eq $tamacCurrent) { 'not installed (see tamac.exe)' } elseif ($tamacCurrent) { 'ok' } else { "v$tamacVersion is older than $tamacMinimum" }) `
    -Fix "Run: $ps tools/setup.ps1 -Tool tamac (downloads the latest release)"

# --- SSP -------------------------------------------------------------------------------
$ssp = Resolve-SspPath
$sspOk = [bool]$ssp
$sspFix = 'Get SSP from https://ssp.shillest.net/ . If it is already installed, ask where ssp.exe is and write it to tools/local.json as {"sspPath": "C:\\path\\to\\ssp.exe"}.'
$sspDetail = 'not found'
if ($ssp) {
    $sspVersion = Get-DevkitSspVersion $ssp.Path
    $sspDetail = "$($ssp.Path) $(if ($sspVersion) { Format-DevkitSspVersion $sspVersion } else { '(version unknown)' }) (found via $($ssp.Source))"
    $sspRecommended = Format-DevkitSspVersion $DevkitSspRecommendedVersion
    if ($sspVersion -and $sspVersion -lt $DevkitSspRecommendedVersion) {
        $sspOk = $false
        $sspDetail += "; older than $sspRecommended"
        $sspFix = "Update SSP to $sspRecommended or later (https://ssp.shillest.net/ , or the network update of SSP itself). The scripts in tools/ are written for it, and may fail or miss problems with older versions."
    }
} else {
    $local = Get-DevkitLocalConfig
    if ($env:SSP_PATH -or ($local -and ($local.PSObject.Properties.Name -contains 'sspPath'))) {
        $sspDetail = 'not found; the path in SSP_PATH or tools/local.json does not exist'
    }
}
Add-DoctorItem -Id 'ssp' -Name "SSP $(Format-DevkitSspVersion $DevkitSspRecommendedVersion)+" -Level 'recommended' -Ok $sspOk `
    -Purpose 'Shell check (tools/check-shell.ps1), running the ghost (tools/run-ssp.ps1), trying talks (tools/sstp.ps1) and reading its logs (tools/ssp-log.ps1), building the nar and network update files (tools/build-nar.ps1)' `
    -Detail $sspDetail `
    -Fix $sspFix

# --- git -------------------------------------------------------------------------------
$git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$gitDetail = 'not found'
if ($git) { $gitDetail = (Invoke-DevkitProcess -FilePath $git.Source -Arguments @('--version') -TimeoutSeconds 30).StdOut.Trim() }
Add-DoctorItem -Id 'git' -Name 'Git' -Level 'recommended' -Ok ([bool]$git) `
    -Purpose 'Version history, GitHub (checks and automatic releases), and the system dictionary submodule in a git clone' `
    -Detail $gitDetail `
    -Fix $(if ($hasWinget) { 'After the user agrees, run: winget install --id Git.Git -e (then restart the terminal)' } else { 'Download from https://git-scm.com/download/win' })

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
