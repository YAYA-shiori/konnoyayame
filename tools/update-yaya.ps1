<#
.SYNOPSIS
    Updates YAYA: ghost/master/yaya.dll and the system dictionary (yaya-dic), and verifies them with check-dic.
.DESCRIPTION
    yaya.dll comes from yaya.zip of https://github.com/YAYA-shiori/yaya-shiori/releases (or -Tag). YAYA is released
    in series side by side (the 500 series and the 600 series; tag TcXYY-N is of series X), and a release is taken
    from the series of the current yaya.dll, whether it is a pre-release or not: the highest tag version of that
    series. -Series takes another series. With no yaya.dll (or one of a series that has no release), the series of
    the latest stable release is used. When a newer series is out, it is only shown.
    yaya.dll is not replaced with an older version than the current one, unless -Tag, -Series or -Force is given.
    The system dictionary comes from https://github.com/YAYA-shiori/yaya-dic, which has no releases: the latest
    commit of its default branch is used. It is looked for in ghost/master/dic/system, then ghost/master/system:
      - a git checkout (such as a submodule): fetched and switched to the latest commit. Nothing is done when the
        folder has uncommitted changes or commits that are not in yaya-dic.
      - plain files (in a git working copy or not): replaced with the files of the latest commit. yaya_base/config.dic
        and _loading_order.txt, which authors may change, are not replaced when they differ; the new version is
        written next to them as <file>.yaya-dic-new. Files that are not in yaya-dic are listed and left as they are.
      - another layout (yaya_shiori3.dic and so on, in system/ or directly in ghost/master): nothing is done. The
        dictionaries have to be reorganized by hand (docs/agents/workflows/update-yaya.md).
    -SystemDicDir places yaya-dic in a folder that does not have it yet (used when reorganizing).
    yaya.dll is updated first. The dictionaries are checked after each part; when the check fails, that part is
    put back and nothing more is updated. When the system dictionary cannot be updated, nothing is changed.
    Exit codes: 0 = updated / already up to date / dry run, 1 = failed,
    2 = the system dictionary needs work by hand (another layout, local changes, or <file>.yaya-dic-new to merge).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-yaya.ps1 -DryRun
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-yaya.ps1 -Tag Tc573-6 -SkipSystemDic
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-yaya.ps1 -Series 6 -DryRun
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-yaya.ps1 -SkipDll -SystemDicDir dic/system
#>
[CmdletBinding()]
param(
    # Release tag of yaya-shiori for yaya.dll (default: the newest release of the series of the current yaya.dll).
    [string]$Tag,
    # Series of YAYA for yaya.dll: 5 = the 500 series, 6 = the 600 series (default: that of the current yaya.dll).
    [ValidateRange(1, 99)]
    [int]$Series,
    # Folder that contains yaya.dll (default: ghost/master).
    [string]$GhostDir,
    # Folder of the system dictionary, relative to ghost/master (default: the one that has yaya-dic).
    [ValidateSet('dic/system', 'system')]
    [string]$SystemDicDir,
    [switch]$SkipDll,
    [switch]$SkipSystemDic,
    [switch]$DryRun,
    # Replace yaya.dll even when it is the same file or an older version.
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/ignore.ps1')
. (Join-Path $PSScriptRoot 'lib/devkit.ps1')
Initialize-DevkitConsole
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ($SkipDll -and $SkipSystemDic) {
    Write-Host 'update-yaya: FAILED - -SkipDll and -SkipSystemDic leave nothing to update'
    exit 1
}
if ($Tag -and $Series) {
    Write-Host 'update-yaya: FAILED - -Tag already chooses the release; do not give -Series with it'
    exit 1
}
if (-not $GhostDir) { $GhostDir = Join-Path $DevkitRoot 'ghost/master' }
$GhostDir = (Resolve-DevkitFullPath $GhostDir).TrimEnd('\', '/')
$dll = Join-Path $GhostDir 'yaya.dll'
$ghostRoot = Split-Path (Split-Path $GhostDir -Parent) -Parent
$dicRepository = 'YAYA-shiori/yaya-dic'
$dicNewSuffix = '.yaya-dic-new'

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
$headers = @{ 'User-Agent' = 'ghost-devkit'; 'Accept' = 'application/vnd.github+json' }
$git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

$exitCode = 0
# 1 (failed) wins over 2 (needs work by hand).
function Set-UpdateExitCode([int]$Code) {
    if ($Code -eq 1 -or $script:exitCode -eq 0) { $script:exitCode = $Code }
}

# Runs check-dic on the ghost and returns its exit code (1 = errors, 3 = tamac.exe is not installed).
function Invoke-DictionaryCheck {
    $powershell = (Get-Process -Id $PID).Path
    $ErrorActionPreference = 'Continue'
    & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check-dic.ps1') -GhostDir $GhostDir | Out-Host
    return $LASTEXITCODE
}

function Invoke-DicGit([string]$Folder, [string[]]$Arguments) {
    $result = Invoke-DevkitProcess -FilePath $git.Source -Arguments (@('-C', $Folder) + $Arguments) -TimeoutSeconds 300
    if ($result.ExitCode -ne 0) { throw "git $($Arguments -join ' ') failed in $Folder : $(($result.StdErr + $result.StdOut).Trim())" }
    return $result.StdOut.Trim()
}

# Files of yaya-dic that authors may change to configure it.
function Test-DicSettingFile([string]$Relative) {
    return ($Relative -ieq 'yaya_base/config.dic' -or $Relative -ieq '_loading_order.txt' -or $Relative -like '*/_loading_order.txt')
}

# Root-relative paths of the files under $Root, without repository files (.git, .github, .vscode, .gitattributes).
function Get-DicFiles([string]$Root) {
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $result = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $rootPath -PathType Container) {
        foreach ($item in @(Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force)) {
            $relative = $item.FullName.Substring($rootPath.Length + 1).Replace('\', '/')
            if ($relative.StartsWith('.')) { continue }
            $result.Add($relative)
        }
    }
    [string[]]$paths = $result.ToArray()
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    return , $paths
}

function Restore-DicFolder([string]$Folder, [string]$Backup, [bool]$Existed) {
    if (Test-Path -LiteralPath $Folder) { Remove-Item -LiteralPath $Folder -Recurse -Force }
    if ($Existed) { Copy-Item -LiteralPath $Backup -Destination $Folder -Recurse -Force }
}

# Version of a yaya-shiori release tag such as Tc602-4 or Tc573-3A ($null for a tag in another form).
function Get-YayaTagVersion([string]$TagName) {
    if ($TagName -match '^Tc(\d+)-(\d+)[A-Za-z]*$') { return New-Object Version -ArgumentList @([int]$matches[1], [int]$matches[2]) }
    return $null
}

# Version of yaya.dll from its file version such as "6, 02, 4, 0" ($null when it cannot be read).
# The major number is the series (6 for Tc602-4).
function ConvertTo-YayaFileVersion([string]$Text) {
    $numbers = @([regex]::Matches([string]$Text, '\d+') | ForEach-Object { [int]$_.Value })
    if ($numbers.Count -lt 3) { return $null }
    return New-Object Version -ArgumentList @($numbers[0], $numbers[1], $numbers[2])
}

# Releases of yaya-shiori that have yaya.zip and a tag of the form TcXYY-N, with their series (X).
function Get-YayaReleaseList {
    $api = 'https://api.github.com/repos/YAYA-shiori/yaya-shiori/releases?per_page=100'
    $list = New-Object System.Collections.Generic.List[object]
    # foreach unrolls the JSON array (Windows PowerShell 5.1 returns it as one object).
    foreach ($release in (Invoke-RestMethod -UseBasicParsing -Uri $api -Headers $headers)) {
        if ($release.draft -or -not @($release.assets | Where-Object { $_.name -eq 'yaya.zip' }).Count) { continue }
        $version = Get-YayaTagVersion ([string]$release.tag_name)
        if (-not $version) { continue }
        $list.Add([pscustomobject]@{ Release = $release; Version = $version; Series = [int][math]::Floor($version.Major / 100); Published = [datetime]$release.published_at })
    }
    return , $list.ToArray()
}

# The newest of the releases: the highest tag version, then the latest date (for Tc573-3 and Tc573-3A).
function Select-YayaNewestRelease([object[]]$Candidates) {
    return @($Candidates | Sort-Object -Property @{ Expression = 'Version'; Descending = $true }, @{ Expression = 'Published'; Descending = $true }) | Select-Object -First 1
}

function Get-YayaReleaseLabel($Release) {
    return "$($Release.tag_name)$(if ($Release.prerelease) { ' (pre-release)' })"
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('devkit-yaya-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    # --- yaya.dll: what to do ----------------------------------------------------------------
    $dllPlan = $null
    if (-not $SkipDll) {
        Write-Host '[yaya.dll]'
        $hasOld = Test-Path -LiteralPath $dll
        $oldVersion = if ($hasOld) { (Get-Item -LiteralPath $dll).VersionInfo.FileVersion } else { '(none)' }
        $oldParsed = ConvertTo-YayaFileVersion $oldVersion
        $newerSeries = $null
        if ($Tag) {
            $release = Invoke-RestMethod -UseBasicParsing -Uri ('https://api.github.com/repos/YAYA-shiori/yaya-shiori/releases/tags/' + [uri]::EscapeDataString($Tag)) -Headers $headers
        } else {
            $candidates = Get-YayaReleaseList
            if ($candidates.Count -eq 0) { throw 'no release of yaya-shiori has yaya.zip' }
            if ($Series) {
                $targetSeries = $Series
                $seriesReason = 'given by -Series'
            } elseif ($oldParsed -and @($candidates | Where-Object { $_.Series -eq $oldParsed.Major }).Count) {
                $targetSeries = $oldParsed.Major
                $seriesReason = 'that of the current yaya.dll'
            } else {
                $stable = @($candidates | Where-Object { -not $_.Release.prerelease } | Sort-Object -Property Published -Descending) | Select-Object -First 1
                if (-not $stable) { $stable = @($candidates | Sort-Object -Property Published -Descending) | Select-Object -First 1 }
                $targetSeries = $stable.Series
                $seriesReason = 'that of the latest stable release'
            }
            $chosen = Select-YayaNewestRelease @($candidates | Where-Object { $_.Series -eq $targetSeries })
            if (-not $chosen) {
                $known = @($candidates | ForEach-Object { "$($_.Series)00" } | Sort-Object -Unique) -join ', '
                throw "no release of the $($targetSeries)00 series has yaya.zip (series found: $known)"
            }
            $release = $chosen.Release
            Write-Host "series  : $($targetSeries)00 ($seriesReason)"
            $newerSeries = Select-YayaNewestRelease @($candidates | Where-Object { $_.Series -gt $targetSeries })
        }
        $asset = @($release.assets | Where-Object { $_.name -eq 'yaya.zip' }) | Select-Object -First 1
        if (-not $asset) { throw "yaya.zip was not found in release $($release.tag_name)" }
        $zipPath = Join-Path $work 'yaya.zip'
        Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $zipPath
        $newDll = Join-Path $work 'yaya.dll'
        $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $entry = @($zip.Entries | Where-Object { $_.Name -eq 'yaya.dll' }) | Select-Object -First 1
            if ($entry) { [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $newDll) }
        } finally {
            $zip.Dispose()
        }
        if (-not (Test-Path -LiteralPath $newDll)) { throw 'yaya.dll is not in yaya.zip' }

        $oldHash = if ($hasOld) { (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash } else { '' }
        $newVersion = (Get-Item -LiteralPath $newDll).VersionInfo.FileVersion
        $newHash = (Get-FileHash -LiteralPath $newDll -Algorithm SHA256).Hash
        Write-Host "current : $oldVersion"
        Write-Host "release : $(Get-YayaReleaseLabel $release) (file version $newVersion)"
        Write-Host "notes   : $($release.html_url)"
        if ($newerSeries) {
            Write-Host "newer   : the $($newerSeries.Series)00 series is out: $(Get-YayaReleaseLabel $newerSeries.Release) $($newerSeries.Release.html_url) (not taken; -Series $($newerSeries.Series) switches to it)"
        }
        $newParsed = ConvertTo-YayaFileVersion $newVersion
        if ($oldHash -eq $newHash -and -not $Force) {
            Write-Host 'update-yaya: yaya.dll is already up to date'
        } elseif ($oldParsed -and $newParsed -and $newParsed -lt $oldParsed -and -not $Tag -and -not $Series -and -not $Force) {
            Write-Host "update-yaya: the release is older than the current yaya.dll, so yaya.dll was kept. -Series or -Tag takes another version"
        } else {
            $dllPlan = [pscustomobject]@{ NewDll = $newDll; HasOld = $hasOld; OldVersion = $oldVersion; NewVersion = $newVersion; Tag = [string]$release.tag_name }
        }
    }

    # --- system dictionary: what to do -------------------------------------------------------
    $dicPlan = $null
    $dicBlocked = $null
    if (-not $SkipSystemDic) {
        $existing = $null
        foreach ($candidate in $DevkitSystemDicDirs) {
            if (Test-DevkitYayaDicLayout (Join-Path $GhostDir $candidate)) { $existing = $candidate; break }
        }
        $dir = $null
        if ($SystemDicDir) {
            $dir = $SystemDicDir
            if ($existing -and $existing -ne $SystemDicDir) { $dicBlocked = "yaya-dic is already in ghost/master/$existing (-SystemDicDir is $SystemDicDir)" }
        } elseif ($existing) {
            $dir = $existing
        } else {
            $dir = Get-DevkitSystemDicDir $GhostDir
        }
        $folder = if ($dir) { Join-Path $GhostDir $dir } else { $null }
        Write-Host $(if ($dir) { "[system dictionary] ghost/master/$dir" } else { '[system dictionary]' })

        # An empty submodule folder of a git clone. A .gitmodules without .git (such as in a nar) does not count.
        $isSubmodulePath = $false
        $gitmodules = Join-Path $ghostRoot '.gitmodules'
        if ($dir -and (Test-Path -LiteralPath (Join-Path $ghostRoot '.git')) -and (Test-Path -LiteralPath $gitmodules -PathType Leaf) -and
            @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            foreach ($line in [IO.File]::ReadAllLines($gitmodules)) {
                if ($line -match '^\s*path\s*=\s*(.+?)\s*$' -and $matches[1].Replace('\', '/').TrimEnd('/') -ieq "ghost/master/$dir") { $isSubmodulePath = $true }
            }
        }

        if ($dicBlocked) {
            # already decided
        } elseif (-not $dir) {
            $oldFiles = @(Find-DevkitOldSystemDicFiles $GhostDir)
            if ($oldFiles.Count -gt 0) {
                $dicBlocked = 'the system dictionary is in another layout than yaya-dic: ' + ($oldFiles -join ', ')
            } else {
                $dicBlocked = 'no system dictionary was found in ' + (($DevkitSystemDicDirs | ForEach-Object { "ghost/master/$_" }) -join ' or ') + '. In a git clone, run tools/setup.ps1 first'
            }
        } elseif ($isSubmodulePath -and -not (Test-Path -LiteralPath (Join-Path $folder '.git'))) {
            $dicBlocked = "ghost/master/$dir is a git submodule that has not been fetched. Run tools/setup.ps1 (git submodule update --init) first"
        } elseif ((Test-Path -LiteralPath $folder -PathType Container) -and -not (Test-DevkitYayaDicLayout $folder) -and
            @(Get-ChildItem -LiteralPath $folder -Force).Count -gt 0) {
            $dicBlocked = "ghost/master/$dir is in another layout than yaya-dic (it has no yaya_base/shiori3.dic)"
            $oldFiles = @(Find-DevkitOldSystemDicFiles $GhostDir)
            if ($oldFiles.Count -gt 0) { $dicBlocked += ': ' + ($oldFiles -join ', ') }
        } elseif (Test-Path -LiteralPath (Join-Path $folder '.git')) {
            # A git checkout of yaya-dic, such as a submodule.
            if (-not $git) { throw "Git is needed to update ghost/master/$dir, which is a git checkout" }
            $remote = Invoke-DicGit $folder @('remote', 'get-url', 'origin')
            $superproject = Invoke-DicGit $folder @('rev-parse', '--show-superproject-working-tree')
            Write-Host "kind    : $(if ($superproject) { 'git submodule' } else { 'git checkout' }) of $remote"
            $oldCommit = Invoke-DicGit $folder @('rev-parse', 'HEAD')
            Write-Host "current : $(Invoke-DicGit $folder @('log', '-1', '--date=short', '--format=%h %ad %s', $oldCommit))"
            Invoke-DicGit $folder @('fetch', '--quiet', 'origin', 'HEAD') | Out-Null
            $newCommit = Invoke-DicGit $folder @('rev-parse', 'FETCH_HEAD')
            Write-Host "latest  : $(Invoke-DicGit $folder @('log', '-1', '--date=short', '--format=%h %ad %s', $newCommit))"
            if ($oldCommit -ne $newCommit -and $remote -match 'github\.com[:/]+([^/]+/[^/]+?)(\.git)?/?$') {
                Write-Host "changes : https://github.com/$($matches[1])/compare/$oldCommit...$newCommit"
            }
            $status = Invoke-DicGit $folder @('status', '--porcelain')
            $isAncestor = (Invoke-DevkitProcess -FilePath $git.Source -Arguments @('-C', $folder, 'merge-base', '--is-ancestor', $oldCommit, $newCommit) -TimeoutSeconds 60).ExitCode -eq 0
            if ($oldCommit -eq $newCommit) {
                Write-Host 'update-yaya: the system dictionary is already up to date'
            } elseif ($status) {
                Write-Host $status
                $dicBlocked = "ghost/master/$dir has uncommitted changes (above). Put them aside (for example git stash) before updating"
            } elseif (-not $isAncestor) {
                $dicBlocked = "ghost/master/$dir is at a commit that is not in the history of $remote (local commits, or a fork)"
            } else {
                Write-Host "commits : $(Invoke-DicGit $folder @('rev-list', '--count', "$oldCommit..$newCommit")) new"
                $dicPlan = [pscustomobject]@{ Mode = 'git'; Dir = $dir; Folder = $folder; OldCommit = $oldCommit; NewCommit = $newCommit; Submodule = [bool]$superproject }
            }
        } else {
            # Plain files, or a folder that does not have yaya-dic yet.
            $existed = Test-Path -LiteralPath $folder -PathType Container
            $commit = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$dicRepository/commits/HEAD" -Headers $headers
            $newCommit = [string]$commit.sha
            if ($newCommit -notmatch '^[0-9a-f]{40}$') { throw "could not find the latest commit of $dicRepository" }
            $date = ([string]$commit.commit.committer.date) -replace 'T.*$', ''
            $subject = ([string]$commit.commit.message).Split("`n")[0].Trim()
            Write-Host "kind    : $(if ($existed -and (Test-DevkitYayaDicLayout $folder)) { 'plain files' } else { 'new' })"
            Write-Host "latest  : $($newCommit.Substring(0, 7)) $date $subject"
            Write-Host "history : https://github.com/$dicRepository/commits/$newCommit"

            $dicZip = Join-Path $work 'yaya-dic.zip'
            Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$dicRepository/archive/$newCommit.zip" -OutFile $dicZip
            $extracted = Join-Path $work 'yaya-dic'
            [IO.Compression.ZipFile]::ExtractToDirectory($dicZip, $extracted)
            $inner = @(Get-ChildItem -LiteralPath $extracted -Directory -Force)
            $sourceRoot = if ($inner.Count -eq 1) { $inner[0].FullName } else { $extracted }
            if (-not (Test-DevkitYayaDicLayout $sourceRoot)) { throw "yaya_base/shiori3.dic was not found in $dicRepository @ $newCommit" }

            $actions = New-Object System.Collections.Generic.List[object]
            $upstream = @{}
            foreach ($relative in (Get-DicFiles $sourceRoot)) {
                $upstream[$relative.ToLowerInvariant()] = $true
                $from = Join-Path $sourceRoot $relative
                $to = Join-Path $folder $relative
                if (-not (Test-Path -LiteralPath $to -PathType Leaf)) {
                    $actions.Add([pscustomobject]@{ Action = 'create'; Path = $relative; From = $from; Note = '' })
                } elseif ((Get-DevkitFileHash $from) -eq (Get-DevkitFileHash $to)) {
                    continue
                } elseif (Test-DicSettingFile $relative) {
                    $actions.Add([pscustomobject]@{ Action = 'CONFLICT'; Path = $relative; From = $from; Note = "differs from yaya-dic; the new version goes to $relative$dicNewSuffix" })
                } else {
                    $actions.Add([pscustomobject]@{ Action = 'update'; Path = $relative; From = $from; Note = '' })
                }
            }
            $extras = New-Object System.Collections.Generic.List[string]
            foreach ($relative in (Get-DicFiles $folder)) {
                if ($relative.EndsWith($dicNewSuffix, [StringComparison]::OrdinalIgnoreCase)) { continue }
                if (-not $upstream.ContainsKey($relative.ToLowerInvariant())) { $extras.Add($relative) }
            }
            foreach ($action in $actions) {
                Write-Host ('  {0,-8} {1}{2}' -f $action.Action, $action.Path, $(if ($action.Note) { " ($($action.Note))" } else { '' }))
            }
            foreach ($relative in $extras) { Write-Host ('  {0,-8} {1} (not in yaya-dic; left as it is)' -f 'extra', $relative) }
            if ($actions.Count -eq 0) {
                Write-Host 'update-yaya: the system dictionary is already up to date'
            } else {
                $dicPlan = [pscustomobject]@{ Mode = 'files'; Dir = $dir; Folder = $folder; Existed = $existed; Actions = $actions; NewCommit = $newCommit }
            }
        }

        if ($dicBlocked) {
            Write-Host "update-yaya: $dicBlocked"
            Write-Host 'update-yaya: the system dictionary needs work by hand (docs/agents/workflows/update-yaya.md). -SkipSystemDic updates only yaya.dll'
            Set-UpdateExitCode 2
        }
    }

    # --- apply ---------------------------------------------------------------------------------
    if ($DryRun) {
        Write-Host 'update-yaya: dry run, nothing changed'
    } elseif ($dicBlocked) {
        Write-Host 'update-yaya: nothing was changed'
    } else {
        $continue = $true
        if ($dllPlan) {
            $backup = Join-Path $work 'yaya.dll.old'
            if ($dllPlan.HasOld) { Copy-Item -LiteralPath $dll -Destination $backup }
            try {
                Copy-Item -LiteralPath $dllPlan.NewDll -Destination $dll -Force
            } catch {
                $continue = $false
                Write-Host "update-yaya: could not replace yaya.dll ($($_.Exception.Message)). If SSP is running this ghost, close the ghost and retry."
                Set-UpdateExitCode 1
            }
            if ($continue) {
                $checkCode = Invoke-DictionaryCheck
                if ($checkCode -eq 1) {
                    if ($dllPlan.HasOld) { Copy-Item -LiteralPath $backup -Destination $dll -Force }
                    Write-Host "update-yaya: the dictionary check failed with the new yaya.dll; restored $($dllPlan.OldVersion)"
                    $continue = $false
                    Set-UpdateExitCode 1
                } else {
                    if ($checkCode -eq 3) { Write-Host 'update-yaya: WARNING - tamac.exe is not installed, so the new yaya.dll was not verified' }
                    Write-Host "update-yaya: updated yaya.dll $($dllPlan.OldVersion) -> $($dllPlan.NewVersion) ($($dllPlan.Tag))"
                }
            }
        }

        if ($dicPlan -and -not $continue) {
            Write-Host 'update-yaya: the system dictionary was not updated'
        } elseif ($dicPlan -and $dicPlan.Mode -eq 'git') {
            Invoke-DicGit $dicPlan.Folder @('checkout', '--quiet', '--detach', $dicPlan.NewCommit) | Out-Null
            $checkCode = Invoke-DictionaryCheck
            if ($checkCode -eq 1) {
                Invoke-DicGit $dicPlan.Folder @('checkout', '--quiet', '--detach', $dicPlan.OldCommit) | Out-Null
                Write-Host "update-yaya: the dictionary check failed with the new system dictionary; restored $($dicPlan.OldCommit.Substring(0, 7))"
                Set-UpdateExitCode 1
            } else {
                if ($checkCode -eq 3) { Write-Host 'update-yaya: WARNING - tamac.exe is not installed, so the new system dictionary was not verified' }
                Write-Host "update-yaya: updated the system dictionary in ghost/master/$($dicPlan.Dir) $($dicPlan.OldCommit.Substring(0, 7)) -> $($dicPlan.NewCommit.Substring(0, 7))"
                if ($dicPlan.Submodule) { Write-Host "update-yaya: ghost/master/$($dicPlan.Dir) is a git submodule; commit it in the ghost repository to record the new commit" }
            }
        } elseif ($dicPlan) {
            $backup = Join-Path $work 'system-dic.old'
            if ($dicPlan.Existed) { Copy-Item -LiteralPath $dicPlan.Folder -Destination $backup -Recurse -Force }
            $conflicts = New-Object System.Collections.Generic.List[string]
            try {
                foreach ($action in $dicPlan.Actions) {
                    $to = Join-Path $dicPlan.Folder $action.Path
                    if ($action.Action -eq 'CONFLICT') {
                        $to += $dicNewSuffix
                        $conflicts.Add($action.Path)
                    }
                    New-Item -ItemType Directory -Force -Path (Split-Path $to -Parent) | Out-Null
                    [IO.File]::Copy($action.From, $to, $true)
                }
            } catch {
                Restore-DicFolder $dicPlan.Folder $backup $dicPlan.Existed
                throw
            }
            $checkCode = Invoke-DictionaryCheck
            if ($checkCode -eq 1) {
                Restore-DicFolder $dicPlan.Folder $backup $dicPlan.Existed
                Write-Host 'update-yaya: the dictionary check failed with the new system dictionary; restored the previous files'
                Set-UpdateExitCode 1
            } else {
                if ($checkCode -eq 3) { Write-Host 'update-yaya: WARNING - tamac.exe is not installed, so the new system dictionary was not verified' }
                Write-Host "update-yaya: updated the system dictionary in ghost/master/$($dicPlan.Dir) to $dicRepository @ $($dicPlan.NewCommit.Substring(0, 7))"
                if ($conflicts.Count -gt 0) {
                    Write-Host "update-yaya: merge each <file>$dicNewSuffix into <file>, then delete it: $(($conflicts | ForEach-Object { "ghost/master/$($dicPlan.Dir)/$_" }) -join ', ')"
                    Set-UpdateExitCode 2
                }
            }
        }
    }
} catch {
    Write-Host "update-yaya: FAILED - $($_.Exception.Message)"
    Set-UpdateExitCode 1
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
exit $exitCode
