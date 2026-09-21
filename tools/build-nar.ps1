<#
.SYNOPSIS
    Builds a distributable .nar archive of the ghost, and the network update files, with SSP.
.DESCRIPTION
    By default, SSP builds everything with "ssp.exe --offline-tool updatedata|nar" (SSP 2.9.01 or later), which
    writes the files and exits without starting the ghost or talking to a running SSP.
    SSP packs the folder as it is, so untracked files of a git working copy are shipped too, and it reads
    .narignore / .updateignore (and .narinclude) itself.
    The nar goes to build/<directory in install.txt>.nar (or -OutFile), and updates2.dau and updates.txt to the
    same folder. SSP does not put an output file inside the ghost folder into the archive or the update data,
    and /build/ is excluded by tools/devkit.narignore. -UpdateOnly writes only the network update files.
    With -Builtin, or on GitHub Actions (GITHUB_ACTIONS=true), where SSP is not available, the nar is written
    by this script instead: in a git working copy, files come from "git ls-files --recurse-submodules", so
    untracked files are never shipped; otherwise the folder itself is used. Paths matched by .narignore
    (gitignore syntax with "include:") are excluded, as are .git metadata and profile folders. .narinclude
    and the network update files are not supported there.
    -ListOnly prints the files that .narignore includes and excludes, as this script reads it.
    Exit codes: 0 = OK, 1 = failed, 3 = ssp.exe was not found.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-nar.ps1 -ListOnly
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-nar.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-nar.ps1 -UpdateOnly
.EXAMPLE
    pwsh ./tools/build-nar.ps1 -OutFile yayame.nar
#>
[CmdletBinding()]
param(
    # Output path of the nar (default: build/<directory in install.txt>.nar). The update files go next to it.
    [string]$OutFile,
    # Print included and excluded files without writing anything.
    [switch]$ListOnly,
    # Write only the network update files (updates2.dau and updates.txt) with SSP.
    [switch]$UpdateOnly,
    # Write the nar with this script instead of SSP (the default on GitHub Actions).
    [switch]$Builtin,
    # -Builtin only: use the files in the folder even when it is a git working copy.
    [switch]$FromWorkingTree,
    # Ask SSP to install the archive after building it.
    [switch]$Install,
    [string]$SspPath,
    # Seconds to wait for SSP to write each file.
    [int]$TimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/ignore.ps1')
Initialize-DevkitConsole
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $DevkitRoot
$useSsp = -not ($Builtin -or $env:GITHUB_ACTIONS -eq 'true')
if ($UpdateOnly -and -not $useSsp) {
    Write-Host 'build-nar: FAILED - the network update files are made only with SSP (not with -Builtin or on GitHub Actions)'
    exit 1
}
if (-not $OutFile) {
    $directoryName = Get-DevkitDescriptValue (Join-Path $root 'install.txt') 'directory'
    if (-not $directoryName) { $directoryName = 'ghost' }
    $OutFile = Join-Path (Join-Path $root 'build') ($directoryName + '.nar')
}
$OutFile = Resolve-DevkitFullPath $OutFile
$outDir = Split-Path $OutFile -Parent

$hasNarInclude = Test-Path -LiteralPath (Join-Path $root '.narinclude')
if ($hasNarInclude -and ($ListOnly -or -not $useSsp)) {
    Write-Host 'build-nar: FAILED - .narinclude (whitelist) is not supported by -ListOnly and -Builtin. Build the nar with SSP (without -Builtin).'
    exit 1
}

function Get-RootRelativePath([string]$FullPath) {
    return $FullPath.Substring($root.Length + 1).Replace('\', '/')
}

# --- collect candidate files ---------------------------------------------------------------
# SSP packs the folder as it is; the builtin writer ships only the files tracked by git.
$files = New-Object System.Collections.Generic.List[string]
$untracked = @()
$git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$isGitCopy = $git -and (Test-Path -LiteralPath (Join-Path $root '.git'))
$useGit = (-not $useSsp) -and (-not $FromWorkingTree) -and $isGitCopy
if ($useGit) {
    $listed = Invoke-DevkitProcess -FilePath $git.Source -Arguments @('-C', $root, 'ls-files', '-z', '--recurse-submodules') -TimeoutSeconds 120
    if ($listed.ExitCode -ne 0) {
        Write-Host "build-nar: git ls-files failed: $($listed.StdErr)"
        exit 1
    }
    foreach ($path in $listed.StdOut.Split([char]0)) {
        if ($path -and (Test-Path -LiteralPath (Join-Path $root $path) -PathType Leaf)) { $files.Add($path) }
    }
} else {
    foreach ($item in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        $files.Add((Get-RootRelativePath $item.FullName))
    }
}
if ($isGitCopy) {
    $others = Invoke-DevkitProcess -FilePath $git.Source -Arguments @('-C', $root, 'ls-files', '-z', '--others', '--exclude-standard') -TimeoutSeconds 120
    if ($others.ExitCode -eq 0) { $untracked = @($others.StdOut.Split([char]0) | Where-Object { $_ }) }
}

# --- exclusion rules -----------------------------------------------------------------------
if (-not (Test-Path -LiteralPath (Join-Path $root '.narignore'))) {
    Write-Host 'build-nar: note - .narignore was not found; only .git and profile folders are excluded'
}
$ignoreMatcher = New-DevkitIgnoreMatcher (Read-DevkitIgnoreRules $root '.narignore')

function Test-Excluded([string]$RelativePath) {
    # Always excluded, as SSP does: git metadata and profile folders.
    $segments = $RelativePath.Split('/')
    if ($segments -contains '.git') { return $true }
    if ($segments.Count -ge 2 -and ($segments[0..($segments.Count - 2)] -contains 'profile')) { return $true }
    return (Test-DevkitIgnored $ignoreMatcher $RelativePath)
}

$outRelative = $null
if ($OutFile.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    $outRelative = Get-RootRelativePath $OutFile
}

$included = New-Object System.Collections.Generic.List[string]
$excluded = New-Object System.Collections.Generic.List[string]
foreach ($relative in ($files | Sort-Object -Unique)) {
    if ($relative -eq $outRelative -or (Test-Excluded $relative)) { $excluded.Add($relative) } else { $included.Add($relative) }
}

# With .narinclude, SSP decides what goes in, so the list above says nothing about the nar.
if (-not $hasNarInclude) {
    if (-not ($included | Where-Object { Test-DevkitSystemDicPath $_ 'ghost/master/' })) {
        $systemDicNames = ($DevkitSystemDicDirs | ForEach-Object { "ghost/master/$_" }) -join ' or '
        Write-Host "build-nar: FAILED - the system dictionary ($systemDicNames) is empty. Run: git submodule update --init"
        exit 1
    }
    if ($included -notcontains 'install.txt') {
        Write-Host 'build-nar: FAILED - install.txt is missing'
        exit 1
    }
}

$untrackedIncluded = @($untracked | Where-Object { $included -contains $_ })
if ($ListOnly) {
    Write-Host "== included ($($included.Count)) =="
    foreach ($relative in $included) { Write-Host "  $relative" }
    Write-Host "== excluded ($($excluded.Count)) =="
    foreach ($relative in $excluded) { Write-Host "  $relative" }
    if ($useSsp -and $untrackedIncluded.Count -gt 0) {
        Write-Host "note: $($untrackedIncluded.Count) file(s) not tracked by git are included, because SSP packs the folder as it is"
    } elseif (-not $useSsp -and $untracked.Count -gt 0) {
        Write-Host "note: $($untracked.Count) untracked file(s) are not included (git add them to ship)"
    }
    exit 0
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
# Keep the default output folder out of git without an entry in the ghost's own .gitignore.
$buildDir = Join-Path $root 'build'
if ($outDir.TrimEnd('\', '/') -ieq $buildDir -and -not (Test-Path -LiteralPath (Join-Path $buildDir '.gitignore'))) {
    [IO.File]::WriteAllText((Join-Path $buildDir '.gitignore'), "*`n", $DevkitUtf8)
}

function Install-Nar {
    $ssp = Resolve-SspPath $SspPath
    if (-not $ssp) {
        Write-Host 'build-nar: ssp.exe was not found, so the archive was not installed'
        return 3
    }
    Start-Process -FilePath $ssp.Path -ArgumentList @('/I', ('"' + $OutFile + '"'))
    Write-Host "build-nar: asked SSP to install $OutFile"
    return 0
}

# --- builtin writer (CI) -------------------------------------------------------------------
if (-not $useSsp) {
    if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force }
    $archive = [IO.Compression.ZipFile]::Open($OutFile, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($relative in $included) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $root $relative), $relative, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally {
        $archive.Dispose()
    }
    $sizeKb = [math]::Round((Get-Item -LiteralPath $OutFile).Length / 1KB)
    Write-Host "build-nar: wrote $OutFile ($($included.Count) files, $sizeKb KB)"
    if ($untracked.Count -gt 0) { Write-Host "build-nar: note - $($untracked.Count) untracked file(s) were not included (git add them to ship)" }
    if ($Install) { exit (Install-Nar) }
    exit 0
}

# --- SSP -----------------------------------------------------------------------------------
$ssp = Resolve-SspPath $SspPath
if (-not $ssp) {
    Write-Host 'build-nar: ssp.exe was not found. Set the SSP_PATH environment variable or create tools/local.json (see tools/local.example.json).'
    exit 3
}

# Output files, in the order SSP writes them. The update files are made first, so that they describe the same
# folder as the nar. "ssp.exe --offline-tool" writes one file per run without starting the ghost.
$jobs = @(
    @{ Kind = 'updatedata'; Path = (Join-Path $outDir 'updates2.dau') },
    @{ Kind = 'updatedata'; Path = (Join-Path $outDir 'updates.txt') }
)
if (-not $UpdateOnly) { $jobs += @{ Kind = 'nar'; Path = $OutFile } }

$exitCode = 0
foreach ($job in $jobs) {
    $arguments = @('--offline-tool', $job.Kind, '--target-dir', $root, '--output', $job.Path)
    $result = Invoke-DevkitProcess -FilePath $ssp.Path -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
    if ($result.TimedOut) {
        Write-Host "build-nar: FAILED - SSP did not finish $($job.Path) within $TimeoutSeconds seconds"
        $exitCode = 1
        break
    }
    if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $job.Path -PathType Leaf)) {
        # ssp.exe --offline-tool: 1 = bad arguments (or an SSP without the option), 2 = could not be written.
        Write-Host "build-nar: FAILED - SSP could not write $($job.Path) (ssp.exe exit code $($result.ExitCode))"
        if ($result.ExitCode -eq 1) {
            Write-Host "build-nar: --offline-tool needs SSP $(Format-DevkitSspVersion $DevkitSspRecommendedVersion) or later ($($ssp.Path))"
        }
        $exitCode = 1
        break
    }
    $sizeKb = [math]::Round((Get-Item -LiteralPath $job.Path).Length / 1KB)
    Write-Host "build-nar: wrote $($job.Path) ($sizeKb KB)"
}
if ($exitCode -ne 0) { exit $exitCode }
if ($untrackedIncluded.Count -gt 0) {
    Write-Host "build-nar: note - $($untrackedIncluded.Count) file(s) not tracked by git were included (SSP packs the folder as it is; see -ListOnly)"
}
if ($Install -and -not $UpdateOnly) { exit (Install-Nar) }
exit 0
