<#
.SYNOPSIS
    Builds a distributable .nar archive of the ghost.
.DESCRIPTION
    In a git working copy, files come from "git ls-files --recurse-submodules", so untracked files
    are never shipped. Otherwise (for example a ghost folder installed in SSP) the folder itself is used.
    Paths matched by .narignore (gitignore syntax with "include:", the same file SSP uses for its nar
    creation) are excluded, as are .git metadata and profile folders. .narinclude is not supported.
    Exit codes: 0 = OK, 1 = failed, 3 = -Install was given but ssp.exe was not found.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-nar.ps1 -ListOnly
.EXAMPLE
    pwsh ./tools/build-nar.ps1 -OutFile yayame.nar
#>
[CmdletBinding()]
param(
    # Output path (default: build/<directory in install.txt>.nar).
    [string]$OutFile,
    # Print included and excluded files without writing the archive.
    [switch]$ListOnly,
    # Use the files in the folder even when it is a git working copy.
    [switch]$FromWorkingTree,
    # Ask SSP to install the archive after building it.
    [switch]$Install,
    [string]$SspPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/ignore.ps1')
Initialize-DevkitConsole
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $DevkitRoot
if (-not $OutFile) {
    $directoryName = Get-DevkitDescriptValue (Join-Path $root 'install.txt') 'directory'
    if (-not $directoryName) { $directoryName = 'ghost' }
    $OutFile = Join-Path (Join-Path $root 'build') ($directoryName + '.nar')
}
$OutFile = Resolve-DevkitFullPath $OutFile

if (Test-Path -LiteralPath (Join-Path $root '.narinclude')) {
    Write-Host 'build-nar: FAILED - .narinclude (whitelist) is not supported by this script. Create the nar with SSP instead.'
    exit 1
}

function Get-RootRelativePath([string]$FullPath) {
    return $FullPath.Substring($root.Length + 1).Replace('\', '/')
}

# --- collect candidate files ---------------------------------------------------------------
$files = New-Object System.Collections.Generic.List[string]
$untracked = 0
$git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$useGit = (-not $FromWorkingTree) -and $git -and (Test-Path -LiteralPath (Join-Path $root '.git'))
if ($useGit) {
    $listed = Invoke-DevkitProcess -FilePath $git.Source -Arguments @('-C', $root, 'ls-files', '-z', '--recurse-submodules') -TimeoutSeconds 120
    if ($listed.ExitCode -ne 0) {
        Write-Host "build-nar: git ls-files failed: $($listed.StdErr)"
        exit 1
    }
    foreach ($path in $listed.StdOut.Split([char]0)) {
        if ($path -and (Test-Path -LiteralPath (Join-Path $root $path) -PathType Leaf)) { $files.Add($path) }
    }
    $others = Invoke-DevkitProcess -FilePath $git.Source -Arguments @('-C', $root, 'ls-files', '-z', '--others', '--exclude-standard') -TimeoutSeconds 120
    if ($others.ExitCode -eq 0) { $untracked = @($others.StdOut.Split([char]0) | Where-Object { $_ }).Count }
} else {
    foreach ($item in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        $files.Add((Get-RootRelativePath $item.FullName))
    }
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

if (-not ($included | Where-Object { Test-DevkitSystemDicPath $_ 'ghost/master/' })) {
    $systemDicNames = ($DevkitSystemDicDirs | ForEach-Object { "ghost/master/$_" }) -join ' or '
    Write-Host "build-nar: FAILED - the system dictionary ($systemDicNames) is empty. Run: git submodule update --init"
    exit 1
}
if ($included -notcontains 'install.txt') {
    Write-Host 'build-nar: FAILED - install.txt is missing'
    exit 1
}

if ($ListOnly) {
    Write-Host "== included ($($included.Count)) =="
    foreach ($relative in $included) { Write-Host "  $relative" }
    Write-Host "== excluded ($($excluded.Count)) =="
    foreach ($relative in $excluded) { Write-Host "  $relative" }
    if ($untracked -gt 0) { Write-Host "note: $untracked untracked file(s) are not included (git add them to ship)" }
    exit 0
}

# --- write the archive ---------------------------------------------------------------------
$outDir = Split-Path $OutFile -Parent
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
# Keep the default output folder out of git without an entry in the ghost's own .gitignore.
$buildDir = Join-Path $root 'build'
if ($outDir.TrimEnd('\', '/') -ieq $buildDir -and -not (Test-Path -LiteralPath (Join-Path $buildDir '.gitignore'))) {
    [IO.File]::WriteAllText((Join-Path $buildDir '.gitignore'), "*`n", $DevkitUtf8)
}
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
if ($untracked -gt 0) { Write-Host "build-nar: note - $untracked untracked file(s) were not included (git add them to ship)" }

if ($Install) {
    $ssp = Resolve-SspPath $SspPath
    if (-not $ssp) {
        Write-Host 'build-nar: ssp.exe was not found, so the archive was not installed'
        exit 3
    }
    Start-Process -FilePath $ssp.Path -ArgumentList @('/I', ('"' + $OutFile + '"'))
    Write-Host "build-nar: asked SSP to install $OutFile"
}
exit 0
