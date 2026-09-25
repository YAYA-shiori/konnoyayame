# Loads the image engine (tools/lib/image.cs) for tools/image.ps1 and tools/dump-surface.ps1.
# Dot-source it after lib/common.ps1.

# Compiles tools/lib/image.cs once per source and PowerShell edition, into the temp folder.
function Import-DevkitImageEngine {
    $source = Join-Path $PSScriptRoot 'image.cs'
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
