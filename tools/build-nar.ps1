<#
.SYNOPSIS
    Builds a distributable .nar archive of the ghost, and the network update files, with SSP.
.DESCRIPTION
    By default, SSP builds everything: the ghost is run in the isolated SSP of
    tools/run-ssp.ps1 (an isolated SSP already running for this folder is reused, one started here is closed
    again), and an Owned SSTP request plays \![execute,createupdatedata,<file>] and \![execute,createnar,<file>].
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
    Exit codes: 0 = OK, 1 = failed, 2 = built, but SSP logged Error or
    Critical entries meanwhile, 3 = ssp.exe was not found.
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
    # Seconds to wait for SSP to write the files.
    [int]$TimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/ignore.ps1')
. (Join-Path $PSScriptRoot 'lib/sstp.ps1')
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
# folder as the nar.
$updateFiles = @((Join-Path $outDir 'updates2.dau'), (Join-Path $outDir 'updates.txt'))
$targets = @($updateFiles)
if (-not $UpdateOnly) { $targets += $OutFile }

# Arguments of \![...] are separated by commas; a quoted argument may contain them.
function ConvertTo-SakuraArgument([string]$Value) {
    if ($Value.Contains('"')) { throw "a path with a double quote cannot be passed to SSP: $Value" }
    if ($Value.IndexOfAny([char[]]@(',', ']')) -ge 0) { return '"' + $Value + '"' }
    return $Value
}
$script = ''
foreach ($file in $updateFiles) { $script += '\![execute,createupdatedata,' + (ConvertTo-SakuraArgument $file) + ']' }
if (-not $UpdateOnly) { $script += '\![execute,createnar,' + (ConvertTo-SakuraArgument $OutFile) + ']' }

# Waits until every file exists, has kept its size for one poll and can be opened exclusively.
function Wait-OutputFiles([string[]]$Paths, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    $sizes = @{}
    while ((Get-Date) -lt $deadline) {
        $ready = $true
        foreach ($path in $Paths) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $ready = $false; continue }
            $size = (Get-Item -LiteralPath $path).Length
            if (-not $sizes.ContainsKey($path) -or $sizes[$path] -ne $size) { $ready = $false }
            $sizes[$path] = $size
            try {
                $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
                $stream.Dispose()
            } catch {
                $ready = $false
            }
        }
        if ($ready) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

$session = Get-DevkitSspSession
$started = $false
if ($session) {
    if ([string]$session.root -ine $root) {
        Write-Host "build-nar: FAILED - an isolated SSP for another folder is running (port $($session.port)): $($session.root)"
        Write-Host 'build-nar: close it first with tools/run-ssp.ps1 -Stop'
        exit 1
    }
    Write-Host "build-nar: using the isolated SSP that is already running (SSTP port $($session.port))"
} else {
    & (Join-Path $PSScriptRoot 'run-ssp.ps1') -SspPath $ssp.Path -Root $root
    $runExit = $LASTEXITCODE
    $session = Get-DevkitSspSession
    if ($session) { $started = $true }
    if (($runExit -ne 0 -and $runExit -ne 2) -or -not $session) {
        Write-Host 'build-nar: FAILED - the ghost could not be started in an isolated SSP'
        if ($started) { & (Join-Path $PSScriptRoot 'run-ssp.ps1') -Stop | Out-Null }
        exit 1
    }
}
$port = [int]$session.port

function Invoke-SspBuild {
    foreach ($path in $targets) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    $sakuraName = Get-DevkitDescriptValue (Join-Path $root 'ghost/master/descript.txt') 'sakura.name'
    # Owned SSTP: without the ID header, SSP ignores \![execute,...] from another program.
    $ghostId = Get-DevkitSspGhostId -GhostRoot $root -SakuraName $sakuraName -Port $port
    if (-not $ghostId) {
        Write-Host "build-nar: FAILED - the ghost was not found in the SSP on port $port"
        return 1
    }
    $marker = New-DevkitSspLogMarker -Kind 'error' -Port $port
    $lines = @('SEND SSTP/1.4', 'Charset: UTF-8', 'Sender: ghost-devkit', ('ID: ' + $ghostId), ('Script: ' + $script))
    $response = Invoke-DevkitSstp -Lines $lines -Port $port -TimeoutSeconds 30
    if ($response.Status -lt 200 -or $response.Status -ge 300) {
        Write-Host "build-nar: FAILED - SSP did not accept the request: $($response.StatusLine)"
        return 1
    }
    Write-Host "build-nar: asked SSP to write $(($targets | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')"
    Wait-DevkitSspTalkEnd -StartSeconds 1 -TimeoutSeconds 60 -Port $port | Out-Null
    $written = Wait-OutputFiles $targets $TimeoutSeconds
    foreach ($path in $targets) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $sizeKb = [math]::Round((Get-Item -LiteralPath $path).Length / 1KB)
            Write-Host "build-nar: wrote $path ($sizeKb KB)"
        } else {
            Write-Host "build-nar: FAILED - SSP did not write $path within $TimeoutSeconds seconds"
        }
    }
    $result = 0
    if (-not $written) { $result = 1 }
    if ($marker) {
        $log = Get-DevkitSspLog -Kind 'error' -Since $marker -Max 30 -Port $port
        if ((Write-DevkitSspLogSummary 'build-nar' $log 30 -Base $root) -and $result -eq 0) { $result = 2 }
    }
    if ($untrackedIncluded.Count -gt 0) {
        Write-Host "build-nar: note - $($untrackedIncluded.Count) file(s) not tracked by git were included (SSP packs the folder as it is; see -ListOnly)"
    }
    return $result
}

$exitCode = 1
try {
    $exitCode = Invoke-SspBuild
} finally {
    if ($started) { & (Join-Path $PSScriptRoot 'run-ssp.ps1') -Stop }
}

if ($exitCode -eq 1) { exit 1 }
if ($Install -and -not $UpdateOnly) {
    $installExit = Install-Nar
    if ($installExit -ne 0) { exit $installExit }
}
exit $exitCode
