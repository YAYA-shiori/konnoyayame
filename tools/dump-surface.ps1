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
    -Sheet also writes sheet.png, which puts every image in one picture with its number, for comparing
    expressions at a glance (needs System.Drawing, which Windows has).
    Messages of SSP at Warning or above are shown; use tools/check-shell.ps1 to check the shell itself.
    Exit codes: 0 = every image was written, 1 = failed (no image, bad arguments, ssp.exe failed),
    2 = some images were written, but a surface number was not found or SSP logged an Error or Critical,
    3 = ssp.exe was not found.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/dump-surface.ps1 -Surface 0,5,10
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/dump-surface.ps1 -Surface 0-7 -Backlog -Sheet
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
    # Also write sheet.png with every image and its number.
    [switch]$Sheet,
    # Output folder (default: a folder in the temp folder). Existing files with the same names are replaced.
    [string]$OutDir,
    [string]$SspPath,
    # Ghost root folder that contains ghost/ and shell/ (default: this repository).
    [string]$Root
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-DevkitConsole

if (-not $Root) { $Root = $DevkitRoot }
$Root = (Resolve-DevkitFullPath $Root).TrimEnd('\', '/')

# "surface10" is passed as "10".
$ids = @($Surface | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() -replace '^surface(\d+)$', '$1' } | Where-Object { $_ })
if ($ids.Count -eq 0) {
    Write-Host 'dump-surface: FAILED - no surface ID was given'
    exit 1
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
if ($defaultOut) {
    Get-ChildItem -LiteralPath $OutDir -Filter '*.png' -File | Remove-Item -Force
}

# Dump into an empty folder first, so that only the images of this run are reported.
$work = Join-Path ([IO.Path]::GetTempPath()) ('devkit-dump-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$log = Join-Path $work 'error.log'
$prefix = if ($Backlog) { 'backlog' } else { 'surface' }
$arguments = @('--offline-dump', $Root, '--dump-surface-list', ($ids -join ','), '--dump-scope', [string]$Scope,
    '--dump-output-dir', $work, '--dump-output-prefix', $prefix, '--dump-error-log', $log)
if ($Shell) { $arguments += @('--dump-shell', $Shell) }
if ($Backlog) { $arguments += @('--dump-surface-option', 'backlog') }

try {
    $result = Invoke-DevkitProcess -FilePath $ssp.Path -Arguments $arguments -TimeoutSeconds 180
    $rows = @()
    if (Test-Path -LiteralPath $log) {
        $rows = @(Import-Csv -LiteralPath $log -Header 'Time', 'Name', 'Level', 'Message' -Encoding UTF8)
    }
    $images = @(Get-ChildItem -LiteralPath $work -Filter '*.png' -File)
    foreach ($image in $images) {
        Move-Item -LiteralPath $image.FullName -Destination (Join-Path $OutDir $image.Name) -Force
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

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

# Sort by the surface number in the file name.
$pattern = '^' + [regex]::Escape($prefix) + '(\d+)\.png$'
$written = @($images | ForEach-Object {
    $number = if ($_.Name -match $pattern) { [int]$matches[1] } else { [int]::MaxValue }
    [pscustomobject]@{ Number = $number; Path = (Join-Path $OutDir $_.Name) }
} | Sort-Object Number, Path)
foreach ($item in $written) { Write-Host $item.Path }

# Only plain numbers can be checked; the extended forms may name surfaces that do not exist on purpose.
$missing = @()
foreach ($id in $ids) {
    if ($id -match '^(\d+)$') {
        $number = [int]$matches[1]
        if (-not ($written | Where-Object { $_.Number -eq $number })) { $missing += $number }
    }
}
if ($missing.Count -gt 0) {
    Write-Host "dump-surface: not written (no such surface in the shell?): $($missing -join ', ')"
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
                    $label = if ($written[$i].Number -eq [int]::MaxValue) { [IO.Path]::GetFileNameWithoutExtension($written[$i].Path) } else { [string]$written[$i].Number }
                    $graphics.DrawString($label, $font, [System.Drawing.Brushes]::Black, $x, $y + $imageHeight + 3)
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

$summary = "$($written.Count) image(s) in $OutDir"
if ($missing.Count -gt 0 -or $errors -gt 0) {
    Write-Host "dump-surface: WARNING ($summary; not found: $($missing.Count), errors: $errors)"
    exit 2
}
Write-Host "dump-surface: OK ($summary)"
exit 0
