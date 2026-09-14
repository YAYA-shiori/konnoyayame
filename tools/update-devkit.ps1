<#
.SYNOPSIS
    Updates the development kit (AGENTS.md, CLAUDE.md, .claude/, tools/ ...) without touching the ghost itself.
.DESCRIPTION
    The kit files are listed in tools/devkit.json. tools/devkit.lock.json records the upstream hash of
    each kit file at the last update, so that changes made by the author are kept:
      - not changed locally          -> replaced with the new version
      - changed locally only         -> kept
      - changed locally and upstream -> kept; the new version is written next to it as <file>.devkit-new
      - removed from the kit         -> deleted, unless it was changed locally
      - deleted locally              -> not restored
    Seed files (GHOST.md, .narignore, ...) are created only when they are missing.
    The new version comes from the latest release of the source repository in tools/devkit.json
    (default), -Ref (tag, branch or commit), or -Source (a local folder or zip that contains tools/devkit.json).
    -Target installs or updates the kit in another YAYA ghost folder.
    For the repository that distributes the kit: -WriteLock rewrites tools/devkit.lock.json from the
    current kit files, and -VerifyLock checks it (skipped on GitHub Actions outside the source repository).
    Exit codes: 0 = updated / up to date / dry run, 1 = failed (or a stale lock with -VerifyLock),
    2 = <file>.devkit-new files are waiting to be merged.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1 -DryRun
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1 -Target C:\ssp\ghost\myghost
#>
[CmdletBinding()]
param(
    # Tag, branch or commit of the source repository (default: its latest release).
    [string]$Ref,
    # Local folder or zip that contains tools/devkit.json, used instead of downloading.
    [string]$Source,
    # Ghost folder to update (default: the ghost that contains this script).
    [string]$Target,
    [switch]$DryRun,
    [switch]$WriteLock,
    [switch]$VerifyLock
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/ignore.ps1')
. (Join-Path $PSScriptRoot 'lib/devkit.ps1')
Initialize-DevkitConsole
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $Target) { $Target = $DevkitRoot }
$Target = (Resolve-DevkitFullPath $Target).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
    Write-Host "update-devkit: FAILED - the target folder was not found: $Target"
    exit 1
}

# --- lock maintenance (the repository that distributes the kit) ---------------------------
if ($WriteLock -or $VerifyLock) {
    if ($WriteLock -and $VerifyLock) {
        Write-Host 'update-devkit: FAILED - use either -WriteLock or -VerifyLock'
        exit 1
    }
    $manifest = Read-DevkitManifest $Target
    if ($VerifyLock -and $env:GITHUB_ACTIONS -eq 'true' -and $env:GITHUB_REPOSITORY -and $env:GITHUB_REPOSITORY -ne $manifest.source) {
        Write-Host "update-devkit: lock check skipped ($env:GITHUB_REPOSITORY does not distribute the kit; the source is $($manifest.source))"
        exit 0
    }
    $current = @{}
    foreach ($relative in (Get-DevkitKitFiles $Target $manifest)) {
        $current[$relative] = Get-DevkitFileHash (Join-Path $Target $relative)
    }
    if ($WriteLock) {
        Write-DevkitLock $Target $manifest.source '' $current
        Write-Host "update-devkit: wrote $DevkitLockName ($($current.Count) files)"
        exit 0
    }
    $lock = Read-DevkitLock $Target
    $stale = New-Object System.Collections.Generic.List[string]
    foreach ($relative in $current.Keys) {
        if (-not $lock.Files.ContainsKey($relative)) { $stale.Add("  added    $relative") }
        elseif ($lock.Files[$relative] -ne $current[$relative]) { $stale.Add("  changed  $relative") }
    }
    foreach ($relative in $lock.Files.Keys) {
        if (-not $current.ContainsKey($relative)) { $stale.Add("  removed  $relative") }
    }
    if ($stale.Count -gt 0) {
        foreach ($line in ($stale | Sort-Object)) { Write-Host $line }
        Write-Host "update-devkit: FAILED - $DevkitLockName is out of date. Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-devkit.ps1 -WriteLock"
        exit 1
    }
    Write-Host "update-devkit: $DevkitLockName is up to date ($($current.Count) files)"
    exit 0
}

# --- update --------------------------------------------------------------------------------
function Copy-DevkitFile([string]$From, [string]$To) {
    New-Item -ItemType Directory -Force -Path (Split-Path $To -Parent) | Out-Null
    [IO.File]::Copy($From, $To, $true)
}

# Removes empty folders from $Folder up to (not including) $Root.
function Remove-DevkitEmptyFolders([string]$Folder, [string]$Root) {
    while ($Folder.Length -gt $Root.Length -and (Test-Path -LiteralPath $Folder -PathType Container)) {
        if (@(Get-ChildItem -LiteralPath $Folder -Force).Count -gt 0) { break }
        Remove-Item -LiteralPath $Folder -Force
        $Folder = Split-Path $Folder -Parent
    }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('devkit-update-' + [guid]::NewGuid().ToString('N'))
$exitCode = 0
try {
    if (-not (Test-Path -LiteralPath (Join-Path $Target 'ghost/master/descript.txt') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $Target 'ghost/master/yaya.dll') -PathType Leaf)) {
        throw "$Target is not a YAYA ghost folder (ghost/master/descript.txt and ghost/master/yaya.dll are needed)"
    }

    # --- get the new version ---------------------------------------------------------------
    $sourceRoot = $null
    $sourceRef = ''
    $sourceLabel = ''
    if ($Source) {
        $Source = (Resolve-DevkitFullPath $Source).TrimEnd('\', '/')
        if (Test-Path -LiteralPath $Source -PathType Container) {
            $sourceRoot = $Source
        } elseif (Test-Path -LiteralPath $Source -PathType Leaf) {
            $extracted = Join-Path $work 'source'
            [IO.Compression.ZipFile]::ExtractToDirectory($Source, $extracted)
            $sourceRoot = $extracted
        } else {
            throw "-Source was not found: $Source"
        }
        if ($Ref) { Write-Host 'update-devkit: note - -Ref is ignored when -Source is given' }
        $sourceLabel = $Source
    } else {
        $manifestRoot = if (Test-Path -LiteralPath (Join-Path $Target $DevkitManifestName)) { $Target } else { $DevkitRoot }
        $repository = [string](Read-DevkitManifest $manifestRoot).source
        if ($repository -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { throw "invalid source in $DevkitManifestName : $repository" }
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        $headers = @{ 'User-Agent' = 'ghost-devkit'; 'Accept' = 'application/vnd.github+json' }
        $api = "https://api.github.com/repos/$repository"
        $refLabel = $Ref
        if (-not $Ref) {
            try {
                $Ref = (Invoke-RestMethod -UseBasicParsing -Uri "$api/releases/latest" -Headers $headers).tag_name
                $refLabel = "latest release $Ref"
            } catch {
                $Ref = (Invoke-RestMethod -UseBasicParsing -Uri $api -Headers $headers).default_branch
                $refLabel = "default branch $Ref (no release was found)"
            }
        }
        if ($Ref -notmatch '^[A-Za-z0-9._/-]+$' -or $Ref.Contains('..')) { throw "invalid -Ref: $Ref" }
        $sourceRef = [string](Invoke-RestMethod -UseBasicParsing -Uri "$api/commits/$Ref" -Headers $headers).sha
        if ($sourceRef -notmatch '^[0-9a-f]{40}$') { throw "could not resolve $Ref to a commit" }
        $zipPath = Join-Path $work 'source.zip'
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$repository/archive/$sourceRef.zip" -OutFile $zipPath
        $extracted = Join-Path $work 'source'
        [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extracted)
        $sourceRoot = $extracted
        $sourceLabel = "$repository @ $sourceRef ($refLabel)"
    }
    # An archive usually has one top folder (for example konnoyayame-<sha>/).
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $DevkitManifestName))) {
        $inner = @(Get-ChildItem -LiteralPath $sourceRoot -Directory -Force | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $DevkitManifestName) })
        if ($inner.Count -ne 1) { throw "$DevkitManifestName was not found in $sourceLabel" }
        $sourceRoot = $inner[0].FullName
    }
    $sourceRoot = [IO.Path]::GetFullPath($sourceRoot).TrimEnd('\', '/')
    if ($sourceRoot -ieq $Target) { throw 'the source and the target are the same folder' }

    # --- decide what to do -----------------------------------------------------------------
    $manifest = Read-DevkitManifest $sourceRoot
    $newFiles = Get-DevkitKitFiles $sourceRoot $manifest
    if ($newFiles.Count -eq 0) { throw "no kit files were found in $sourceLabel" }
    $lock = Read-DevkitLock $Target
    $newLock = @{}
    $actions = New-Object System.Collections.Generic.List[object]
    function Add-DevkitAction([string]$Action, [string]$Path, [string]$From, [string]$Note) {
        $actions.Add([pscustomobject]@{ Action = $Action; Path = $Path; From = $From; Note = $Note })
    }

    foreach ($relative in $newFiles) {
        $from = Join-Path $sourceRoot $relative
        $to = Join-Path $Target $relative
        $new = Get-DevkitFileHash $from
        $base = if ($lock.Files.ContainsKey($relative)) { $lock.Files[$relative] } else { $null }
        if (-not (Test-Path -LiteralPath $to -PathType Leaf)) {
            if ($null -eq $base) {
                Add-DevkitAction 'create' $relative $from ''
                $newLock[$relative] = $new
            } else {
                Add-DevkitAction 'skip' $relative '' 'deleted locally; not restored'
                $newLock[$relative] = $base
            }
            continue
        }
        $local = Get-DevkitFileHash $to
        $newLock[$relative] = $new
        if ($local -eq $new) {
            Add-DevkitAction 'same' $relative '' ''
        } elseif ($null -ne $base -and $local -eq $base) {
            Add-DevkitAction 'update' $relative $from ''
        } elseif ($null -ne $base -and $base -eq $new) {
            Add-DevkitAction 'keep' $relative '' 'changed locally; not changed upstream'
        } else {
            $why = if ($null -eq $base) { 'differs from the kit and has no record in the lock' } else { 'changed locally and upstream' }
            Add-DevkitAction 'conflict' $relative $from "$why; new version -> $relative$DevkitConflictSuffix"
        }
    }
    foreach ($relative in @($lock.Files.Keys)) {
        if ($newFiles -contains $relative) { continue }
        $to = Join-Path $Target $relative
        if (-not (Test-Path -LiteralPath $to -PathType Leaf)) { continue }
        if ((Get-DevkitFileHash $to) -eq $lock.Files[$relative]) {
            Add-DevkitAction 'delete' $relative '' 'removed from the kit'
        } else {
            Add-DevkitAction 'keep' $relative '' 'removed from the kit, but changed locally; delete it if it is no longer needed'
        }
    }
    if ($manifest.seed) {
        foreach ($entry in $manifest.seed.PSObject.Properties) {
            $from = Join-Path $sourceRoot ([string]$entry.Value)
            if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { throw "seed source $($entry.Value) was not found in $sourceLabel" }
            if (-not (Test-Path -LiteralPath (Join-Path $Target $entry.Name))) {
                Add-DevkitAction 'seed' $entry.Name $from 'created because it was missing'
            }
        }
    }

    # --- report ----------------------------------------------------------------------------
    $previous = if ($lock.Ref) { $lock.Ref } elseif ($lock.Exists) { '(unknown version)' } else { '(no lock; first install)' }
    Write-Host "source  : $sourceLabel"
    Write-Host "target  : $Target"
    Write-Host "current : $previous"
    foreach ($action in $actions) {
        if ($action.Action -eq 'same') { continue }
        $label = if ($action.Action -eq 'conflict') { 'CONFLICT' } else { $action.Action }
        $line = '  {0,-8} {1}' -f $label, $action.Path
        if ($action.Note) { $line += " ($($action.Note))" }
        Write-Host $line
    }
    $counts = @{}
    foreach ($action in $actions) { $counts[$action.Action] = 1 + [int]$counts[$action.Action] }
    $summary = @('create', 'update', 'seed', 'delete', 'keep', 'skip', 'conflict', 'same') |
        Where-Object { $counts[$_] } | ForEach-Object { "$($counts[$_]) $_" }
    Write-Host "summary : $($summary -join ', ')"

    if ($DryRun) {
        Write-Host 'update-devkit: dry run, nothing changed'
    } else {
        # --- apply -------------------------------------------------------------------------
        foreach ($action in $actions) {
            $to = Join-Path $Target $action.Path
            switch ($action.Action) {
                'create' { Copy-DevkitFile $action.From $to }
                'update' { Copy-DevkitFile $action.From $to }
                'seed' { Copy-DevkitFile $action.From $to }
                'conflict' { Copy-DevkitFile $action.From ($to + $DevkitConflictSuffix) }
                'delete' {
                    Remove-Item -LiteralPath $to -Force
                    Remove-DevkitEmptyFolders (Split-Path $to -Parent) $Target
                }
            }
        }
        Write-DevkitLock $Target ([string]$manifest.source) $sourceRef $newLock
        Write-Host "update-devkit: updated $Target"
    }

    $pending = @(Get-DevkitConflictFiles $Target)
    if ($pending.Count -gt 0) {
        Write-Host ''
        Write-Host 'update-devkit: merge each file below into the file without .devkit-new, then delete the .devkit-new file:'
        foreach ($relative in $pending) { Write-Host "  $relative" }
        if (-not $DryRun) { $exitCode = 2 }
    }

    if (-not $DryRun) {
        $doctor = Join-Path $Target 'tools/doctor.ps1'
        if (Test-Path -LiteralPath $doctor) {
            Write-Host ''
            Write-Host '==== environment (tools/doctor.ps1) ===='
            $powershell = (Get-Process -Id $PID).Path
            $ErrorActionPreference = 'Continue'
            & $powershell -NoProfile -ExecutionPolicy Bypass -File $doctor
            $ErrorActionPreference = 'Stop'
        }
    }
} catch {
    Write-Host "update-devkit: FAILED - $($_.Exception.Message)"
    $exitCode = 1
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
exit $exitCode
