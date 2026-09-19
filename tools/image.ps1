<#
.SYNOPSIS
    Reads, edits, compares and previews images (mainly shell images). Every image it writes is a 32-bit RGBA PNG.
.DESCRIPTION
    Subcommands:
      info FILE...         size, how the file stores transparency, visible area, pixel values (-At x,y).
                           info and view accept wildcards (shell/master/*.png).
                           For a file in a shell folder, also tells what SSP uses as transparency there
                           (seriko.use_self_alpha of the shell's descript.txt).
      edit INPUT OPS...    applies the operations in order and writes -Out. INPUT is a file or new:WxH[:#color].
      view FILE...         writes a magnified preview with pixel rulers (and the images side by side) to look at.
      diff A B             compares two images; -Part writes the differing pixels of B as a part to paste.
    Each operation is one argument: its name, then positional values and key=value options, separated by
    spaces ('crop 10,20,100,80', 'resize 200x filter=lanczos', "text 'Hello' 5,5 size=12 color=#ff0000").
    The list of operations is in docs/agents/commands.md; the engine is tools/lib/image.cs (C#, compiled once
    into the temp folder). PNG files are read and written by the engine itself; the drawing operations, text
    and non-PNG input use System.Drawing.
    Coordinates are pixels from the top-left (0,0). Colors are #rgb, #rrggbb, #rrggbbaa, black, white or
    transparent. Without -Out, view and diff write to ghost-devkit/image/ in the temp folder.
    Exit codes: 0 = OK, 1 = failed (bad arguments, unreadable file, unknown operation),
    2 = edit wrote the image, but SSP will not use its alpha channel as it is (see the note).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/image.ps1 info shell/master/surface0000.png -At 10,20
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/image.ps1 edit shell/master/surface0000.png -Out work/s0.png colorkey 'crop 80,40,100,100'
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/image.ps1 view work/s0.png -Rect 90,90,60,40 -Zoom 8
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/image.ps1 diff surface0000.png surface0001.png -Part work/face1.png
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('info', 'edit', 'view', 'diff')]
    [string]$Command,
    # info/view: files. edit: the input, then the operations. diff: the two files.
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments,
    # edit: the PNG file to write (required). view/diff -View: where to write the preview.
    [string]$Out,
    # info: pixels to print, as x,y pairs (several: -At 1,2,3,4).
    [string[]]$At,
    # view: only this area x,y,w,h of each image.
    [string[]]$Rect,
    # view: magnification (default: fits about 480 pixels).
    [int]$Zoom = 0,
    # view: grid and ruler step in image pixels (default: chosen from the magnification).
    [int]$Grid = 0,
    # view: checker, white, black, #rrggbb, alpha (the alpha channel as gray) or opaque (colors without alpha).
    [string]$Background = 'checker',
    # diff: largest difference per channel that still counts as equal.
    [int]$Tolerance = 0,
    # diff: write the differing pixels of the second image, cropped, to this PNG.
    [string]$Part,
    # diff: also write a preview of A, B and the differences.
    [switch]$View
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-DevkitConsole

# Compiles tools/lib/image.cs once per source and PowerShell edition, into the temp folder.
function Import-DevkitImageEngine {
    $source = Join-Path $PSScriptRoot 'lib/image.cs'
    $code = [IO.File]::ReadAllText($source)
    $core = $PSVersionTable.PSEdition -eq 'Core'
    $edition = if ($core) { 'core' + $PSVersionTable.PSVersion.Major + '.' + $PSVersionTable.PSVersion.Minor } else { 'desktop' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash($DevkitUtf8.GetBytes($code + "`n" + $edition))
    } finally {
        $sha.Dispose()
    }
    $hash = -join ($bytes[0..7] | ForEach-Object { $_.ToString('x2') })
    $dir = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'ghost-devkit') 'image'
    $dll = Join-Path $dir "engine-$edition-$hash.dll"
    $references = @('System.Drawing')
    if ($core) {
        # PowerShell 7 moves parts of System.Drawing into assemblies that have no reference assembly and differ
        # between .NET versions (System.Private.Windows.GdiPlus since .NET 10); reference those by location.
        Add-Type -AssemblyName System.Drawing
        $references = @('System.Drawing.Common', 'System.Drawing.Primitives', 'System.IO.Compression', 'System.Collections', 'System.Runtime.InteropServices', 'System.ComponentModel.TypeConverter')
        foreach ($name in [System.Drawing.Bitmap].Assembly.GetReferencedAssemblies()) {
            if ($name.Name -notlike 'System.Private.Windows*') { continue }
            try {
                $location = [Reflection.Assembly]::Load($name).Location
                if ($location) { $references += $location }
            } catch { }
        }
    }
    if (-not (Test-Path -LiteralPath $dll)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $temp = Join-Path $dir ("engine-" + [guid]::NewGuid().ToString('N') + '.dll')
        try {
            Add-Type -TypeDefinition $code -ReferencedAssemblies $references -OutputAssembly $temp -OutputType Library
            if (-not (Test-Path -LiteralPath $dll)) { Move-Item -LiteralPath $temp -Destination $dll }
            # Remove the engines built from older sources (one that is in use cannot be removed; it stays).
            Get-ChildItem -LiteralPath $dir -Filter "engine-$edition-*.dll" -File | Where-Object { $_.FullName -ne $dll } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        } catch {
            # The cache could not be written: compile in memory for this run.
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
            Add-Type -TypeDefinition $code -ReferencedAssemblies $references
            return
        } finally {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }
    }
    Add-Type -Path $dll
}

# Returns the value of seriko.use_self_alpha for an image in a shell folder ('0' when it is not set),
# or $null when the image is not in a shell folder. Also returns the path of that descript.txt.
function Get-ShellSelfAlpha([string]$ImagePath) {
    $dir = Split-Path -Parent $ImagePath
    while ($dir) {
        $descript = Join-Path $dir 'descript.txt'
        if (Test-Path -LiteralPath $descript -PathType Leaf) {
            $type = Get-DevkitDescriptValue $descript 'type'
            $parent = Split-Path -Parent $dir
            if ($type -eq 'shell' -or ($parent -and (Split-Path -Leaf $parent) -eq 'shell')) {
                $value = Get-DevkitDescriptValue $descript 'seriko.use_self_alpha'
                if (-not $value) { $value = '0' }
                return [pscustomobject]@{ Value = $value.ToLowerInvariant(); Descript = $descript }
            }
            return $null
        }
        $next = Split-Path -Parent $dir
        if ($next -eq $dir) { break }
        $dir = $next
    }
    return $null
}

function Resolve-ImagePath([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $here $Path))
}

# Expands wildcards in file arguments (powershell -File passes them as they are). new:WxH stays as it is.
function Expand-ImageFiles([string[]]$Files) {
    $result = @()
    foreach ($file in $Files) {
        if ($file -match '^new:' -or -not [Management.Automation.WildcardPattern]::ContainsWildcardCharacters($file)) { $result += $file; continue }
        $pattern = if ([IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $here $file }
        $found = @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { $_.FullName })
        if ($found.Count -eq 0) { throw [GhostDevkit.Imaging.ImageException]::new("no file matches $file") }
        $result += $found
    }
    return $result
}

function Join-Numbers([string[]]$Values) {
    if (-not $Values) { return $null }
    return (($Values | ForEach-Object { [string]$_ }) -join ',')
}

$Arguments = @($Arguments | Where-Object { $_ -ne $null })
$here = (Get-Location).ProviderPath
$imageDir = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'ghost-devkit') 'image'

try {
    Import-DevkitImageEngine
} catch {
    Write-Host "image: FAILED - could not compile tools/lib/image.cs: $($_.Exception.Message)"
    exit 1
}

$exitCode = 0
try {
    switch ($Command) {
        'info' {
            if ($Arguments.Count -eq 0) { throw [GhostDevkit.Imaging.ImageException]::new('info: give one or more image files') }
            # "-At 1,2" arrives as two values; pair the numbers up again.
            $points = @()
            $numbers = @()
            $joined = Join-Numbers $At
            if ($joined) { $numbers = @($joined -split ',') }
            if ($numbers.Count % 2 -ne 0) { throw [GhostDevkit.Imaging.ImageException]::new('-At: give x,y pairs') }
            for ($i = 0; $i -lt $numbers.Count; $i += 2) { $points += "$($numbers[$i].Trim()),$($numbers[$i + 1].Trim())" }
            foreach ($file in (Expand-ImageFiles $Arguments)) {
                $selfAlpha = $null
                if ($file -notmatch '^new:') {
                    $shell = Get-ShellSelfAlpha (Resolve-ImagePath $file)
                    if ($shell) { $selfAlpha = $shell.Value }
                }
                foreach ($line in [GhostDevkit.Imaging.Commands]::Info($here, $file, [string[]]$points, $selfAlpha)) { Write-Host $line }
            }
        }
        'edit' {
            if ($Arguments.Count -eq 0) { throw [GhostDevkit.Imaging.ImageException]::new('edit: give the input file (or new:WxH) and the operations') }
            if (-not $Out) { throw [GhostDevkit.Imaging.ImageException]::new('edit: give the output file with -Out') }
            $operations = [string[]]@($Arguments | Select-Object -Skip 1)
            foreach ($line in [GhostDevkit.Imaging.Commands]::Edit($here, $Arguments[0], $Out, $operations)) { Write-Host $line }
            $outPath = Resolve-ImagePath $Out
            $pna = [IO.Path]::ChangeExtension($outPath, '.pna')
            if (Test-Path -LiteralPath $pna) {
                Write-Host "image: note - $pna is next to the output. The output has its own alpha channel; remove the .pna (or rewrite it) so that SSP does not use it instead."
                $exitCode = 2
            }
            $shell = Get-ShellSelfAlpha $outPath
            if ($shell -and $shell.Value -ne '1' -and $shell.Value -ne 'true' -and $shell.Value -ne 'full') {
                Write-Host "image: note - the output is in a shell whose descript.txt ($($shell.Descript)) does not set seriko.use_self_alpha,1. SSP ignores the alpha channel there and makes the top-left color transparent instead. Add seriko.use_self_alpha,1 to that descript.txt (images without alpha keep the top-left color as before)."
                $exitCode = 2
            }
        }
        'view' {
            if ($Arguments.Count -eq 0) { throw [GhostDevkit.Imaging.ImageException]::new('view: give one or more image files') }
            if (-not $Out) { $Out = Join-Path $imageDir 'view.png' }
            foreach ($line in [GhostDevkit.Imaging.View]::Files($here, [string[]]@(Expand-ImageFiles $Arguments), (Join-Numbers $Rect), $Zoom, $Grid, $Background, $Out)) { Write-Host "view: $line" }
        }
        'diff' {
            if ($Arguments.Count -ne 2) { throw [GhostDevkit.Imaging.ImageException]::new('diff: give two image files') }
            $viewOut = $null
            if ($View) { $viewOut = if ($Out) { Resolve-ImagePath $Out } else { Join-Path $imageDir 'diff.png' } }
            $different = $false
            foreach ($line in [GhostDevkit.Imaging.Commands]::Diff($here, $Arguments[0], $Arguments[1], $Tolerance, $Part, $viewOut, [ref]$different)) { Write-Host $line }
        }
    }
} catch {
    $e = $_.Exception
    while ($e.InnerException -and -not ($e -is [GhostDevkit.Imaging.ImageException])) { $e = $e.InnerException }
    Write-Host "image: FAILED - $($e.Message)"
    exit 1
}
exit $exitCode
