<#
.SYNOPSIS
    Renders surfaces of the shell to PNG files with "ssp.exe --offline-dump", so that they can be looked at.
.DESCRIPTION
    SSP composes each surface as surfaces.txt defines it (element, base animations) and writes
    <prefix><id>.png without starting the ghost. Surfaces that do not exist are skipped by SSP; this script
    reports the plain surface numbers that were asked for but not written.
    The images are written to a temporary folder by default (ghost-devkit/surfaces-<hash> in the temp
    folder; its PNG files are removed before each run), because the license of a shell may forbid
    redistributing modified images. Do not commit the output or put it into the ghost folder.
    -Backlog writes the area around the face (the backlog image, about 80x80) instead of the whole surface.
    -Collision draws the collision areas (their shapes and names) on the images, for checking where
    the Head, Bust and other areas of surfaces.txt are.
    -Animation plays one animation of surfaces.txt as \i[ID] does and also writes the image of every pattern it
    advances, as <prefix><id>_0000.png, _0001.png, ... after <prefix><id>.png. Use it to
    look at the frames of an animation (blinking, lip-sync) one by one.
    -Bind sets the dressing-up state: "category,part" to turn a part on, "category,part,0" to turn it off,
    separated by ";" (the part may be empty or __ALL__ for the whole category). The other parts keep the
    defaults of the shell's descript.txt, not the state the user last chose.
    -Sheet also writes sheet.png, which puts every image in one picture with its number, for comparing
    expressions or the frames of an animation at a glance (needs System.Drawing, which Windows has).
    -Compare renders the same surfaces from a git revision (HEAD, a commit, a tag) or from another folder of
    the ghost, and compares each pair pixel by pixel: how many pixels differ, where, and by how much. For each
    surface that changed it writes compare-<name>.png, a magnified view of the changed area (before, after
    and the differing pixels in red). The images of the other side go to the compare folder of the output.
    Use it to confirm that an edit changed only what was meant, down to a single pixel.
    Messages of SSP at Warning or above are shown; use tools/check-shell.ps1 to check the shell itself.
    Exit codes: 0 = every image was written, 1 = failed (no image, bad arguments, ssp.exe failed),
    2 = some images were written, but a surface number was not found, no frame of -Animation was written,
    or SSP logged an Error or Critical, 3 = ssp.exe was not found.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/dump-surface.ps1 -Surface 0,5,10
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/dump-surface.ps1 -Surface 0-7 -Backlog -Sheet
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/dump-surface.ps1 -Surface 0,10 -Collision
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/dump-surface.ps1 -Surface 0-30 -Compare HEAD
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/dump-surface.ps1 -Surface 0 -Animation 0 -Backlog -Sheet
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/dump-surface.ps1 -Surface 0 -Bind 'Head,Hat;Accessory,,0'
#>
[CmdletBinding()]
param(
    # Surface IDs: numbers, or the extended form of surfaces.txt such as "0-7" (passed to --dump-surface-list).
    [Parameter(Mandatory = $true)]
    [string[]]$Surface,
    # Scope ID of the character (--dump-scope, default 0).
    [int]$Scope = 0,
    # Shell folder name under shell/, or the name of the shell (default: the default shell of the ghost).
    [string]$Shell,
    # Write only the area around the face (--dump-surface-option backlog).
    [switch]$Backlog,
    # Draw the collision areas with their names (--dump-surface-option collision).
    [switch]$Collision,
    # One animation ID (a number or the name given in surfaces.txt) whose frames are also written (--dump-animation).
    [string]$Animation,
    # Dressing-up state: "category,part[,1|0]" items separated by ";" (--dump-bind).
    [string[]]$Bind,
    # Also write sheet.png with every image and its number.
    [switch]$Sheet,
    # Output folder (default: a folder in the temp folder). Existing files with the same names are replaced.
    [string]$OutDir,
    # Compare with the surfaces of a git revision (HEAD, a commit, a tag) or of another folder of the ghost.
    [string]$Compare,
    [string]$SspPath,
    # Ghost root folder that contains ghost/ and shell/ (default: this repository).
    [string]$Root
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/image-engine.ps1')
Initialize-DevkitConsole

if (-not $Root) { $Root = $DevkitRoot }
$Root = (Resolve-DevkitFullPath $Root).TrimEnd('\', '/')

# "surface10" is passed as "10".
$ids = @($Surface | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() -replace '^surface(\d+)$', '$1' } | Where-Object { $_ })
if ($ids.Count -eq 0) {
    Write-Host 'dump-surface: FAILED - no surface ID was given'
    exit 1
}
$Animation = $Animation.Trim()
if ($Animation -match ',') {
    Write-Host 'dump-surface: FAILED - -Animation takes only one animation ID'
    exit 1
}
# SSP does not trim the names, so the spaces around the separators are removed here.
$bindSpec = ''
if ($Bind) {
    $bindSpec = @($Bind | ForEach-Object { $_ -split ';' } | ForEach-Object { (@($_ -split ',') | ForEach-Object { $_.Trim() }) -join ',' } | Where-Object { $_ }) -join ';'
}

# SSP falls back to the default shell when --dump-shell names no shell, so check it here.
if ($Shell) {
    $shellRoot = Join-Path $Root 'shell'
    $found = $false
    if (Test-Path -LiteralPath (Join-Path $shellRoot $Shell) -PathType Container) {
        $found = $true
    } elseif (Test-Path -LiteralPath $shellRoot -PathType Container) {
        foreach ($dir in Get-ChildItem -LiteralPath $shellRoot -Directory) {
            if ((Get-DevkitDescriptValue (Join-Path $dir.FullName 'descript.txt') 'name') -eq $Shell) { $found = $true; break }
        }
    }
    if (-not $found) {
        Write-Host "dump-surface: FAILED - no shell named '$Shell' in shell/ (give the folder name or the name in its descript.txt)"
        exit 1
    }
}

$ssp = Resolve-SspPath $SspPath
if (-not $ssp) {
    Write-Host 'dump-surface: SKIPPED - ssp.exe was not found. Set the SSP_PATH environment variable or create tools/local.json (see tools/local.example.json).'
    exit 3
}

$defaultOut = -not $OutDir
if ($defaultOut) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash($DevkitUtf8.GetBytes($Root.ToLowerInvariant()))
    } finally {
        $sha.Dispose()
    }
    $hash = -join ($bytes[0..7] | ForEach-Object { $_.ToString('x2') })
    $OutDir = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'ghost-devkit') "surfaces-$hash"
} else {
    $OutDir = Resolve-DevkitFullPath $OutDir
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$compareDir = Join-Path $OutDir 'compare'
if ($defaultOut) {
    Get-ChildItem -LiteralPath $OutDir -Filter '*.png' -File | Remove-Item -Force
    if (Test-Path -LiteralPath $compareDir) { Get-ChildItem -LiteralPath $compareDir -Filter '*.png' -File | Remove-Item -Force }
}

# Dumps the surfaces of the ghost in $DumpRoot into an empty folder first, so that only the images of this run
# are reported, then moves them to $Destination.
function Invoke-SurfaceDump([string]$DumpRoot, [string]$Destination) {
    $work = Join-Path ([IO.Path]::GetTempPath()) ('devkit-dump-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    $log = Join-Path $work 'error.log'
    $arguments = @('--offline-dump', $DumpRoot, '--dump-surface-list', ($ids -join ','), '--dump-scope', [string]$Scope,
        '--dump-output-dir', $work, '--dump-output-prefix', $prefix, '--dump-error-log', $log)
    if ($Shell) { $arguments += @('--dump-shell', $Shell) }
    if ($Animation) { $arguments += @('--dump-animation', $Animation) }
    if ($bindSpec) { $arguments += @('--dump-bind', $bindSpec) }
    # SSP reads only the last --dump-surface-option, so the options are given as one comma-separated value.
    $options = @()
    if ($Backlog) { $options += 'backlog' }
    if ($Collision) { $options += 'collision' }
    if ($options.Count -gt 0) { $arguments += @('--dump-surface-option', ($options -join ',')) }
    try {
        $run = Invoke-DevkitProcess -FilePath $ssp.Path -Arguments $arguments -TimeoutSeconds 180
        $logRows = @()
        if (Test-Path -LiteralPath $log) {
            $logRows = @(Import-Csv -LiteralPath $log -Header 'Time', 'Name', 'Level', 'Message' -Encoding UTF8)
        }
        $names = @()
        foreach ($image in @(Get-ChildItem -LiteralPath $work -Filter '*.png' -File)) {
            Move-Item -LiteralPath $image.FullName -Destination (Join-Path $Destination $image.Name) -Force
            $names += $image.Name
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    return [pscustomobject]@{ Result = $run; Rows = $logRows; Names = $names }
}

# Returns the folder to compare with and its label: -Compare itself when it is a folder, otherwise the shell
# and the ghost's descript.txt of that git revision, extracted into a temporary folder ($Temporary = $true).
function Resolve-CompareRoot([string]$Value) {
    if (Test-Path -LiteralPath $Value -PathType Container) {
        $folder = (Resolve-DevkitFullPath $Value).TrimEnd('\', '/')
        if (-not (Test-Path -LiteralPath (Join-Path $folder 'shell') -PathType Container)) { throw "$folder has no shell folder" }
        return [pscustomobject]@{ Root = $folder; Label = (Split-Path -Leaf $folder); Temporary = $false }
    }
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $git) { throw "'$Value' is not a folder, and git was not found to read it as a revision" }
    $commit = Invoke-DevkitProcess -FilePath $git.Source -Arguments @('-C', $Root, 'rev-parse', '--verify', '--quiet', '--short', "$Value^{commit}") -TimeoutSeconds 60
    if ($commit.ExitCode -ne 0) { throw "'$Value' is neither a folder nor a git revision of $Root" }
    # The ghost may be in a subfolder of the repository; archive that subfolder's tree.
    $prefix = Invoke-DevkitProcess -FilePath $git.Source -Arguments @('-C', $Root, 'rev-parse', '--show-prefix') -TimeoutSeconds 60
    $tree = $Value + ':' + $prefix.StdOut.Trim()
    $folder = Join-Path ([IO.Path]::GetTempPath()) ('devkit-compare-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $folder | Out-Null
    $zip = Join-Path $folder 'tree.zip'
    $paths = @('shell')
    $descript = Invoke-DevkitProcess -FilePath $git.Source -Arguments @('-C', $Root, 'cat-file', '-e', ($tree + 'ghost/master/descript.txt')) -TimeoutSeconds 60
    if ($descript.ExitCode -eq 0) { $paths += 'ghost/master/descript.txt' }
    $archive = Invoke-DevkitProcess -FilePath $git.Source -Arguments (@('-C', $Root, 'archive', '--format=zip', '-o', $zip, $tree, '--') + $paths) -TimeoutSeconds 120
    if ($archive.ExitCode -ne 0) {
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
        throw "git archive failed: $($archive.StdErr.Trim())"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $folder)
    Remove-Item -LiteralPath $zip -Force
    return [pscustomobject]@{ Root = $folder; Label = "$Value ($($commit.StdOut.Trim()))"; Temporary = $true }
}

$prefix = if ($Backlog) { 'backlog' } else { 'surface' }
$dump = Invoke-SurfaceDump $Root $OutDir
$result = $dump.Result
$rows = $dump.Rows
$images = @($dump.Names | ForEach-Object { Get-Item -LiteralPath (Join-Path $OutDir $_) })

if ($result.TimedOut) {
    Write-Host 'dump-surface: FAILED - ssp.exe timed out'
    exit 1
}

$errors = 0
foreach ($row in $rows) {
    $level = [string]$row.Level
    if ($level -match '^(error|fatal|critical)$') { $errors++ } elseif ($level -ne 'warning') { continue }
    Write-Host "[$level] $(ConvertTo-DevkitRelativeText ([string]$row.Message) -Base $Root)"
}

# Returns the surface number, the frame of -Animation (-1 for the surface itself) and the label ("0", "0_0003")
# of an image written by SSP: <prefix><id>.png, or <prefix><id>_0000.png and so on for the frames.
$pattern = '^' + [regex]::Escape($prefix) + '(\d+)(?:_(\d+))?\.png$'
function Get-DumpImageInfo([string]$Name) {
    if ($Name -match $pattern) {
        if ($matches[2]) {
            return [pscustomobject]@{ Number = [int]$matches[1]; Frame = [int]$matches[2]; Label = ($matches[1] + '_' + $matches[2]) }
        }
        return [pscustomobject]@{ Number = [int]$matches[1]; Frame = -1; Label = $matches[1] }
    }
    return [pscustomobject]@{ Number = [int]::MaxValue; Frame = -1; Label = [IO.Path]::GetFileNameWithoutExtension($Name) }
}

# Sort by the surface number in the file name, then by the frame.
$written = @($images | ForEach-Object {
    $info = Get-DumpImageInfo $_.Name
    [pscustomobject]@{ Number = $info.Number; Frame = $info.Frame; Label = $info.Label; Path = (Join-Path $OutDir $_.Name) }
} | Sort-Object Number, Frame, Path)
foreach ($item in $written) { Write-Host $item.Path }

# Only plain numbers can be checked; the extended forms may name surfaces that do not exist on purpose.
$missing = @()
foreach ($id in $ids) {
    if ($id -match '^(\d+)$') {
        $number = [int]$matches[1]
        if (-not ($written | Where-Object { $_.Number -eq $number -and $_.Frame -lt 0 })) { $missing += $number }
    }
}
if ($missing.Count -gt 0) {
    Write-Host "dump-surface: not written (no such surface in the shell?): $($missing -join ', ')"
}

# SSP logs a Warning for each surface that does not have the animation and writes only its usual image.
$noFrames = $false
if ($Animation) {
    $frames = @($written | Where-Object { $_.Frame -ge 0 })
    if ($frames.Count -eq 0) {
        $noFrames = $true
        Write-Host "dump-surface: no frame of animation '$Animation' was written (no surface has it, or it cannot be played)"
    } else {
        foreach ($group in @($frames | Group-Object Number | Sort-Object { [int]$_.Name })) {
            Write-Host "animation ${Animation}: surface $($group.Name): $($group.Count) frame(s)"
        }
    }
}

if ($written.Count -eq 0) {
    Write-Host "dump-surface: FAILED - no image was written (ssp.exe exited with code $($result.ExitCode))"
    exit 1
}

if ($Sheet) {
    try {
        Add-Type -AssemblyName System.Drawing
        $bitmaps = @($written | ForEach-Object { [System.Drawing.Image]::FromFile($_.Path) })
        try {
            $cellWidth = [int]($bitmaps | ForEach-Object { $_.Width } | Measure-Object -Maximum).Maximum
            $imageHeight = [int]($bitmaps | ForEach-Object { $_.Height } | Measure-Object -Maximum).Maximum
            $labelHeight = 20
            $gap = 8
            $columns = [Math]::Min($bitmaps.Count, [Math]::Max(1, [int][Math]::Floor(1600 / ($cellWidth + $gap))))
            $rowsCount = [int][Math]::Ceiling($bitmaps.Count / $columns)
            $sheetImage = New-Object System.Drawing.Bitmap([int]($columns * ($cellWidth + $gap) + $gap), [int]($rowsCount * ($imageHeight + $labelHeight + $gap) + $gap))
            $graphics = [System.Drawing.Graphics]::FromImage($sheetImage)
            try {
                $graphics.Clear([System.Drawing.Color]::White)
                $font = New-Object System.Drawing.Font('Arial', 14, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
                $border = New-Object System.Drawing.Pen([System.Drawing.Color]::LightGray)
                for ($i = 0; $i -lt $bitmaps.Count; $i++) {
                    $x = $gap + ($i % $columns) * ($cellWidth + $gap)
                    $y = $gap + [int][Math]::Floor($i / $columns) * ($imageHeight + $labelHeight + $gap)
                    $graphics.DrawRectangle($border, $x - 1, $y - 1, $cellWidth + 1, $imageHeight + 1)
                    $graphics.DrawImage($bitmaps[$i], $x, $y, $bitmaps[$i].Width, $bitmaps[$i].Height)
                    $graphics.DrawString($written[$i].Label,$font, [System.Drawing.Brushes]::Black, $x, $y + $imageHeight + 3)
                }
                $font.Dispose()
                $border.Dispose()
            } finally {
                $graphics.Dispose()
            }
            $sheetPath = Join-Path $OutDir 'sheet.png'
            $sheetImage.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $sheetImage.Dispose()
            Write-Host "sheet: $sheetPath"
        } finally {
            foreach ($bitmap in $bitmaps) { $bitmap.Dispose() }
        }
    } catch {
        Write-Host "dump-surface: note - could not write sheet.png: $($_.Exception.Message)"
    }
}

if ($Compare) {
    $other = $null
    try {
        $other = Resolve-CompareRoot $Compare
        New-Item -ItemType Directory -Force -Path $compareDir | Out-Null
        $otherDump = Invoke-SurfaceDump $other.Root $compareDir
        Import-DevkitImageEngine
    } catch {
        Write-Host "dump-surface: FAILED - could not compare with ${Compare}: $($_.Exception.Message)"
        exit 1
    } finally {
        if ($other -and $other.Temporary) { Remove-Item -LiteralPath $other.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "compare: $($other.Label) -> now (images of $($other.Label) in $compareDir)"
    $counts = @{ Same = 0; Changed = 0; New = 0; Gone = 0 }
    foreach ($item in $written) {
        $name = Split-Path -Leaf $item.Path
        $label = $item.Label
        if ($otherDump.Names -notcontains $name) {
            Write-Host "  ${label}: new (not in $($other.Label))"
            $counts.New++
            continue
        }
        $different = $false
        $line = [GhostDevkit.Imaging.Commands]::Compare((Join-Path $compareDir $name), $item.Path, $other.Label, 'now', (Join-Path $OutDir ('compare-' + $name)), [ref]$different)
        if ($different) { $counts.Changed++ } else { $counts.Same++ }
        Write-Host "  ${label}: $line"
    }
    foreach ($name in $otherDump.Names) {
        if ($written | Where-Object { (Split-Path -Leaf $_.Path) -eq $name }) { continue }
        Write-Host "  $((Get-DumpImageInfo $name).Label): gone (only in $($other.Label))"
        $counts.Gone++
    }
    Write-Host "compare: $($counts.Changed) changed, $($counts.Same) identical, $($counts.New) new, $($counts.Gone) gone"
}

$summary = "$($written.Count) image(s) in $OutDir"
if ($missing.Count -gt 0 -or $errors -gt 0 -or $noFrames) {
    $details = "not found: $($missing.Count), errors: $errors"
    if ($noFrames) { $details += ', no frame of the animation' }
    Write-Host "dump-surface: WARNING ($summary; $details)"
    exit 2
}
Write-Host "dump-surface: OK ($summary)"
exit 0
