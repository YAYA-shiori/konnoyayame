# Helpers for the development kit updater (tools/update-devkit.ps1) and tools/doctor.ps1.
# Dot-source after common.ps1 and ignore.ps1:
#   . (Join-Path $PSScriptRoot 'lib/common.ps1')
#   . (Join-Path $PSScriptRoot 'lib/ignore.ps1')
#   . (Join-Path $PSScriptRoot 'lib/devkit.ps1')
# tools/devkit.json lists the kit-owned files ("files" minus "exclude", gitignore-style globs) and the
# seed files ("seed": destination -> source in the kit), which are created only when they are missing.
# tools/devkit.lock.json records the upstream hash of each kit file at the last update.

$DevkitManifestName = 'tools/devkit.json'
$DevkitLockName = 'tools/devkit.lock.json'
$DevkitConflictSuffix = '.devkit-new'
$DevkitGhostTemplateMarker = '<!-- devkit:ghost-template -->'

function Read-DevkitManifest([string]$Root) {
    $path = Join-Path $Root $DevkitManifestName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$DevkitManifestName was not found in $Root" }
    return ([IO.File]::ReadAllText($path, $DevkitUtf8) | ConvertFrom-Json)
}

function New-DevkitGlobRegex([string]$Glob) {
    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    $body = ConvertFrom-DevkitIgnoreGlob $Glob.TrimStart('/')
    return (New-Object System.Text.RegularExpressions.Regex(('^' + $body + '$'), $options))
}

# Returns the root-relative paths (ordinal order) of the kit-owned files that exist under $Root.
function Get-DevkitKitFiles([string]$Root, $Manifest) {
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $excludes = @($Manifest.exclude | Where-Object { $_ } | ForEach-Object { New-DevkitGlobRegex $_ })
    $found = @{}
    foreach ($glob in @($Manifest.files)) {
        $regex = New-DevkitGlobRegex $glob
        # Only walk the folder before the first segment that has a wildcard.
        $segments = $glob.TrimStart('/').Split('/')
        $literal = New-Object System.Collections.Generic.List[string]
        foreach ($segment in $segments) {
            if ($segment -match '[\*\?\[]') { break }
            $literal.Add($segment)
        }
        $basePath = if ($literal.Count -eq 0) { $rootPath } else { Join-Path $rootPath ($literal -join '/') }
        $candidates = @()
        if ($literal.Count -eq $segments.Count) {
            if (Test-Path -LiteralPath $basePath -PathType Leaf) { $candidates = @(Get-Item -LiteralPath $basePath -Force) }
        } elseif (Test-Path -LiteralPath $basePath -PathType Container) {
            $candidates = @(Get-ChildItem -LiteralPath $basePath -Recurse -File -Force)
        }
        foreach ($item in $candidates) {
            $relative = $item.FullName.Substring($rootPath.Length + 1).Replace('\', '/')
            if (-not $regex.IsMatch($relative)) { continue }
            $excluded = $false
            foreach ($exclude in $excludes) {
                if ($exclude.IsMatch($relative)) { $excluded = $true; break }
            }
            if (-not $excluded) { $found[$relative] = $true }
        }
    }
    [string[]]$paths = @($found.Keys)
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    return , $paths
}

# SHA256 of a file with CRLF normalized to LF, so that a checkout with other line endings still matches.
# Files that contain a NUL byte are hashed as they are.
function Get-DevkitFileHash([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ([Array]::IndexOf($bytes, [byte]0) -lt 0 -and [Array]::IndexOf($bytes, [byte]13) -ge 0) {
        $stream = New-Object System.IO.MemoryStream($bytes.Length)
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            if ($bytes[$i] -eq 13 -and $i + 1 -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { continue }
            $stream.WriteByte($bytes[$i])
        }
        $bytes = $stream.ToArray()
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

function Read-DevkitLock([string]$Root) {
    $lock = [pscustomobject]@{ Exists = $false; Source = ''; Ref = ''; Files = @{} }
    $path = Join-Path $Root $DevkitLockName
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $json = [IO.File]::ReadAllText($path, $DevkitUtf8) | ConvertFrom-Json
        $lock.Exists = $true
        if ($json.source) { $lock.Source = [string]$json.source }
        if ($json.ref) { $lock.Ref = [string]$json.ref }
        if ($json.files) {
            foreach ($property in $json.files.PSObject.Properties) { $lock.Files[$property.Name] = [string]$property.Value }
        }
    }
    return $lock
}

function ConvertTo-DevkitJsonString([string]$Value) {
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

# Writes the lock with sorted keys and LF line endings, so that it diffs well in git.
function Write-DevkitLock([string]$Root, [string]$Source, [string]$Ref, [hashtable]$Files) {
    [string[]]$keys = @($Files.Keys)
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('{')
    $lines.Add('  "source": ' + (ConvertTo-DevkitJsonString $Source) + ',')
    $lines.Add('  "ref": ' + (ConvertTo-DevkitJsonString $Ref) + ',')
    $lines.Add('  "files": {')
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $separator = if ($i -lt $keys.Count - 1) { ',' } else { '' }
        $lines.Add('    ' + (ConvertTo-DevkitJsonString $keys[$i]) + ': ' + (ConvertTo-DevkitJsonString $Files[$keys[$i]]) + $separator)
    }
    $lines.Add('  }')
    $lines.Add('}')
    $path = Join-Path $Root $DevkitLockName
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    [IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), $DevkitUtf8)
}

# Lists the <file>.devkit-new files left by an update (root-relative paths). Wrap the call in @().
function Get-DevkitConflictFiles([string]$Root) {
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $pattern = '*' + $DevkitConflictSuffix
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-ChildItem -LiteralPath $rootPath -File -Force -ErrorAction SilentlyContinue)) { $items.Add($item) }
    foreach ($folder in @('.claude', '.github', 'docs', 'tools')) {
        $path = Join-Path $rootPath $folder
        if (Test-Path -LiteralPath $path -PathType Container) {
            foreach ($item in @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue)) { $items.Add($item) }
        }
    }
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        if ($item.Name -like $pattern) { $result.Add($item.FullName.Substring($rootPath.Length + 1).Replace('\', '/')) }
    }
    return $result.ToArray()
}
