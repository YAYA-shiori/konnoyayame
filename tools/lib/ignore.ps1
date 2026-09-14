# gitignore-style matcher for .narignore / .updateignore (used by tools/build-nar.ps1).
# Dot-source after common.ps1: . (Join-Path $PSScriptRoot 'lib/ignore.ps1')
# Supports comments, "!" negation, leading and trailing "/", "*", "?", "[...]", "**",
# backslash escapes, and the ukagaka-specific "include:<file>" line.
# Matching is case-insensitive, as file names are on Windows.

# Converts one gitignore glob (without leading "/" and trailing "/") into a regex body.
function ConvertFrom-DevkitIgnoreGlob([string]$Glob) {
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $Glob.Length) {
        $c = $Glob[$i]
        if ($c -eq '*' -and $i + 1 -lt $Glob.Length -and $Glob[$i + 1] -eq '*') {
            $atSegmentStart = ($i -eq 0) -or ($Glob[$i - 1] -eq '/')
            $next = if ($i + 2 -lt $Glob.Length) { $Glob[$i + 2] } else { $null }
            if ($atSegmentStart -and $next -eq '/') {
                # "**/" : zero or more directories
                [void]$sb.Append('(?:.*/)?')
                $i += 3
                continue
            }
            if ($atSegmentStart -and $null -eq $next) {
                # trailing "/**" or a lone "**" : everything
                [void]$sb.Append('.*')
                $i += 2
                continue
            }
            [void]$sb.Append('[^/]*')
            $i += 2
            continue
        }
        if ($c -eq '*') {
            [void]$sb.Append('[^/]*')
        } elseif ($c -eq '?') {
            [void]$sb.Append('[^/]')
        } elseif ($c -eq '[' -and $i + 2 -lt $Glob.Length -and $Glob.IndexOf(']', $i + 2) -gt 0) {
            $end = $Glob.IndexOf(']', $i + 2)
            $body = $Glob.Substring($i + 1, $end - $i - 1)
            if ($body.StartsWith('!')) { $body = '^' + $body.Substring(1) }
            [void]$sb.Append('[' + $body + ']')
            $i = $end
        } elseif ($c -eq '\' -and $i + 1 -lt $Glob.Length) {
            $i++
            [void]$sb.Append([regex]::Escape([string]$Glob[$i]))
        } else {
            [void]$sb.Append([regex]::Escape([string]$c))
        }
        $i++
    }
    return $sb.ToString()
}

# Reads rules from an ignore file relative to $Root. Returns a List of rule objects.
function Read-DevkitIgnoreRules([string]$Root, [string]$FileName, [hashtable]$Visited) {
    if ($null -eq $Visited) { $Visited = @{} }
    $rules = New-Object System.Collections.Generic.List[object]
    $path = Join-Path $Root $FileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return , $rules }
    $key = [IO.Path]::GetFullPath($path)
    if ($Visited.ContainsKey($key)) { return , $rules }
    $Visited[$key] = $true

    foreach ($rawLine in [IO.File]::ReadAllLines($path, $DevkitUtf8)) {
        $line = $rawLine.TrimStart([char]0xFEFF)
        if ($line.StartsWith('include:')) {
            foreach ($rule in (Read-DevkitIgnoreRules $Root $line.Substring(8).Trim() $Visited)) { $rules.Add($rule) }
            continue
        }
        # Trailing spaces are ignored unless escaped with a backslash.
        $line = [regex]::Replace($line, '(?<!\\)[ \t]+$', '')
        if ($line -eq '' -or $line.StartsWith('#')) { continue }

        $negate = $false
        if ($line.StartsWith('!')) {
            $negate = $true
            $line = $line.Substring(1)
        } elseif ($line.StartsWith('\!') -or $line.StartsWith('\#')) {
            $line = $line.Substring(1)
        }

        $directoryOnly = $line.EndsWith('/')
        $line = $line.TrimEnd('/')
        if ($line -eq '') { continue }

        # A "/" at the beginning or in the middle anchors the pattern to the root.
        $anchored = $line.Contains('/')
        $body = ConvertFrom-DevkitIgnoreGlob $line.TrimStart('/')
        $pattern = if ($anchored) { '^' + $body + '$' } else { '(?:^|/)' + $body + '$' }
        $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        $rules.Add([pscustomobject]@{
                Regex         = New-Object System.Text.RegularExpressions.Regex($pattern, $options)
                Negate        = $negate
                DirectoryOnly = $directoryOnly
                Source        = $rawLine
            })
    }
    return , $rules
}

function New-DevkitIgnoreMatcher($Rules) {
    return [pscustomobject]@{ Rules = $Rules; DirectoryCache = @{} }
}

# The last matching rule wins.
function Test-DevkitIgnoreRule($Rules, [string]$Path, [bool]$IsDirectory) {
    $ignored = $false
    foreach ($rule in $Rules) {
        if ($rule.DirectoryOnly -and -not $IsDirectory) { continue }
        if ($rule.Regex.IsMatch($Path)) { $ignored = -not $rule.Negate }
    }
    return $ignored
}

# Tests a root-relative file path ("a/b/c.txt"). As in git, a file inside an ignored
# directory cannot be re-included by a negated pattern.
function Test-DevkitIgnored($Matcher, [string]$RelativePath) {
    $segments = $RelativePath.Split('/')
    $directory = ''
    for ($i = 0; $i -lt $segments.Count - 1; $i++) {
        $directory = if ($i -eq 0) { $segments[0] } else { $directory + '/' + $segments[$i] }
        if (-not $Matcher.DirectoryCache.ContainsKey($directory)) {
            $Matcher.DirectoryCache[$directory] = Test-DevkitIgnoreRule $Matcher.Rules $directory $true
        }
        if ($Matcher.DirectoryCache[$directory]) { return $true }
    }
    return (Test-DevkitIgnoreRule $Matcher.Rules $RelativePath $false)
}
