# Shared helpers for the development kit scripts in tools/.
# Dot-source it from a script: . (Join-Path $PSScriptRoot 'lib/common.ps1')
# Keep every tools/*.ps1 file ASCII-only and compatible with Windows PowerShell 5.1.

$DevkitRoot = [IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..') '..')).TrimEnd('\', '/')
$DevkitToolsDir = Join-Path $DevkitRoot 'tools'
$DevkitBinDir = Join-Path $DevkitToolsDir 'bin'
$DevkitUtf8 = New-Object System.Text.UTF8Encoding($false)
# SSP version that the kit is written for: GetStatus, Option: strict, SERIKO error places and --dump-error-log exit codes.
$DevkitSspRecommendedVersion = New-Object System.Version(2, 8, 94)
# Folders of the system dictionary (yaya-dic), relative to ghost/master, in the order they are looked for.
# Most ghosts keep it in dic/system; some keep it in system.
$DevkitSystemDicDirs = @('dic/system', 'system')

function Initialize-DevkitConsole {
    try { [Console]::OutputEncoding = $DevkitUtf8 } catch { }
    try { $global:OutputEncoding = $DevkitUtf8 } catch { }
}

# Resolves a possibly relative path against the PowerShell location (not the process directory).
function Resolve-DevkitFullPath([string]$Path) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Get-DevkitToolManifest {
    $path = Join-Path $DevkitToolsDir 'tools.json'
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-DevkitToolPath([string]$Name) {
    $entry = (Get-DevkitToolManifest).$Name
    if ($null -eq $entry) { throw "Unknown tool: $Name" }
    return (Join-Path $DevkitBinDir $entry.exe)
}

# Tells whether an installed tool is recent enough for the kit: $null when it is not installed, $false when it is out
# of date, $true otherwise (also when that cannot be told). Works offline.
# - Tools that follow the latest release (version "latest"): the file version must be minimumVersion or later.
# - Pinned tools (version, url, sha256): the file must match the pinned SHA256, which changes when a kit update
#   raises the version. Only single-file tools (type exe) can be compared.
function Test-DevkitToolCurrent([string]$Name) {
    $entry = (Get-DevkitToolManifest).$Name
    if ($null -eq $entry) { throw "Unknown tool: $Name" }
    $path = Join-Path $DevkitBinDir $entry.exe
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    if ($entry.version -eq 'latest') {
        $version = Get-DevkitFileVersion $path
        if (-not $version -or -not $entry.minimumVersion) { return $true }
        return ($version -ge [version]$entry.minimumVersion)
    }
    if ($entry.type -ne 'exe') { return $true }
    return ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $entry.sha256)
}

# Returns the file version of a program (for example 1.0.3.25), or $null when it has none.
function Get-DevkitFileVersion([string]$Path) {
    try {
        $info = (Get-Item -LiteralPath $Path).VersionInfo
        if ($info.FileMajorPart -gt 0 -or $info.FileMinorPart -gt 0) {
            return (New-Object System.Version($info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart))
        }
    } catch { }
    return $null
}

# Looks up an asset in the latest release of a GitHub repository. Returns Tag, Url and Sha256 (from the digest that
# GitHub publishes for each asset; $null when there is none). GITHUB_TOKEN is used when it is set, which avoids the
# rate limit of anonymous API requests on GitHub Actions; when the token is refused, the request is sent without it.
function Get-DevkitLatestReleaseAsset([string]$Repository, [string]$AssetName) {
    if ($Repository -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { throw "invalid repository: $Repository" }
    $uri = "https://api.github.com/repos/$Repository/releases/latest"
    $headers = @{ 'User-Agent' = 'ghost-devkit'; 'Accept' = 'application/vnd.github+json' }
    $release = $null
    if ($env:GITHUB_TOKEN) {
        $withToken = $headers.Clone()
        $withToken['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN
        try { $release = Invoke-RestMethod -UseBasicParsing -Uri $uri -Headers $withToken } catch { }
    }
    if (-not $release) { $release = Invoke-RestMethod -UseBasicParsing -Uri $uri -Headers $headers }
    $asset = @($release.assets | Where-Object { $_.name -eq $AssetName }) | Select-Object -First 1
    if (-not $asset) { throw "$AssetName was not found in the latest release ($($release.tag_name)) of $Repository" }
    $sha256 = $null
    if ([string]$asset.digest -match '^sha256:([0-9a-fA-F]{64})$') { $sha256 = $matches[1].ToUpperInvariant() }
    return [pscustomobject]@{ Tag = [string]$release.tag_name; Url = [string]$asset.browser_download_url; Sha256 = $sha256 }
}

# Runs tamac.exe on the yaya.dll in $GhostDir (a full path: tamac.exe looks for yaya.txt in the folder part of the
# dll path it is given). YAYA saves yaya_variable.cfg when it unloads, so the file is put back afterwards (or removed
# when there was none) and running the ghost this way leaves nothing behind.
function Invoke-DevkitTamac {
    param(
        [string]$GhostDir,
        [string[]]$Arguments = @(),
        [string]$InputText,
        [string[]]$UnsetEnvironment = @(),
        [int]$TimeoutSeconds = 120
    )
    $processArgs = @{
        FilePath         = (Get-DevkitToolPath 'tamac')
        Arguments        = @(Join-Path $GhostDir 'yaya.dll') + @($Arguments)
        WorkingDirectory = $GhostDir
        UnsetEnvironment = $UnsetEnvironment
        TimeoutSeconds   = $TimeoutSeconds
    }
    if ($PSBoundParameters.ContainsKey('InputText')) { $processArgs['InputText'] = $InputText }

    $variableFile = Join-Path $GhostDir 'yaya_variable.cfg'
    $variableBackup = $null
    if (Test-Path -LiteralPath $variableFile) {
        $variableBackup = [IO.Path]::GetTempFileName()
        Copy-Item -LiteralPath $variableFile -Destination $variableBackup -Force
    }
    try {
        return (Invoke-DevkitProcess @processArgs)
    } finally {
        if ($variableBackup) {
            Copy-Item -LiteralPath $variableBackup -Destination $variableFile -Force
            Remove-Item -LiteralPath $variableBackup -Force
        } elseif (Test-Path -LiteralPath $variableFile) {
            Remove-Item -LiteralPath $variableFile -Force
        }
    }
}

function Get-DevkitLocalConfig {
    $path = Join-Path $DevkitToolsDir 'local.json'
    if (Test-Path -LiteralPath $path) {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    return $null
}

# Reads "key,value" from descript.txt / install.txt style files (UTF-8).
function Get-DevkitDescriptValue([string]$Path, [string]$Key) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in [IO.File]::ReadAllLines($Path, $DevkitUtf8)) {
        $idx = $line.IndexOf(',')
        if ($idx -gt 0 -and $line.Substring(0, $idx).Trim() -eq $Key) {
            return $line.Substring($idx + 1).Trim()
        }
    }
    return $null
}

function Get-SspPathFromNarAssociation {
    try {
        $progId = $null
        foreach ($key in @('HKCU:\Software\Classes\.nar', 'Registry::HKEY_CLASSES_ROOT\.nar')) {
            if (Test-Path -LiteralPath $key) {
                $progId = (Get-ItemProperty -LiteralPath $key).'(default)'
                if ($progId) { break }
            }
        }
        if (-not $progId) { return $null }
        $commandKey = "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command"
        if (-not (Test-Path -LiteralPath $commandKey)) { return $null }
        $command = (Get-ItemProperty -LiteralPath $commandKey).'(default)'
        if ($command -match '^\s*"([^"]+)"') { return $matches[1] }
        if ($command -match '^\s*(\S+)') { return $matches[1] }
    } catch { }
    return $null
}

# Returns the system dictionary folder (for example 'dic/system', relative to ghost/master) that contains
# .dic files, or $null when none of $DevkitSystemDicDirs does (such as an empty git submodule).
function Get-DevkitSystemDicDir([string]$GhostDir) {
    if (-not $GhostDir) { $GhostDir = Join-Path $DevkitRoot 'ghost/master' }
    foreach ($dir in $DevkitSystemDicDirs) {
        $full = Join-Path $GhostDir $dir
        if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
        if (Get-ChildItem -LiteralPath $full -Recurse -File -Filter '*.dic' -ErrorAction SilentlyContinue | Select-Object -First 1) { return $dir }
    }
    return $null
}

# Tells whether a folder holds the current layout of yaya-dic (yaya_base/shiori3.dic, since June 2022).
function Test-DevkitYayaDicLayout([string]$Folder) {
    return (Test-Path -LiteralPath (Join-Path $Folder 'yaya_base/shiori3.dic') -PathType Leaf)
}

# File names of the system dictionary in older layouts: yaya-dic before June 2022 kept yaya_*.dic in one folder
# (yaya_config.dic only for a day), and older templates kept the settings dictionary as ghost/master/yaya_config.txt.
$DevkitOldSystemDicNames = @('yaya_shiori3.dic', 'yaya_optional.dic', 'yaya_compatible.dic', 'yaya_config.dic', 'yaya_config.txt')

# Returns the files under ghost/master (relative, '/'-separated) that have an old system dictionary file name.
# The ghost may keep them in ghost/master itself, in system/, or anywhere else. Wrap the call in @().
function Find-DevkitOldSystemDicFiles([string]$GhostDir) {
    if (-not $GhostDir) { $GhostDir = Join-Path $DevkitRoot 'ghost/master' }
    $root = [IO.Path]::GetFullPath($GhostDir).TrimEnd('\', '/')
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        if ($DevkitOldSystemDicNames -notcontains $item.Name.ToLowerInvariant()) { continue }
        $relative = $item.FullName.Substring($root.Length + 1).Replace('\', '/')
        if ($relative -match '(^|/)\.git/') { continue }
        $result.Add($relative)
    }
    [string[]]$paths = $result.ToArray()
    [Array]::Sort($paths, [StringComparer]::OrdinalIgnoreCase)
    return $paths
}

# Tells whether a '/'-separated path is inside a system dictionary folder.
# Prefix: what the path starts with before those folders ('' for paths relative to ghost/master).
function Test-DevkitSystemDicPath([string]$Path, [string]$Prefix = '') {
    foreach ($dir in $DevkitSystemDicDirs) {
        if ($Path.StartsWith("$Prefix$dir/", [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# Finds ssp.exe. Order: explicit argument, SSP_PATH, tools/local.json, the SSP that
# this ghost is installed in (<ssp>/ghost/<name>/), then the .nar file association.
function Resolve-SspPath([string]$Explicit) {
    $candidates = New-Object System.Collections.Generic.List[object]
    if ($Explicit) { $candidates.Add(@('-SspPath argument', $Explicit, $true)) }
    if ($env:SSP_PATH) { $candidates.Add(@('SSP_PATH environment variable', $env:SSP_PATH, $true)) }
    $local = Get-DevkitLocalConfig
    if ($local -and ($local.PSObject.Properties.Name -contains 'sspPath') -and $local.sspPath) {
        $candidates.Add(@('tools/local.json', [string]$local.sspPath, $true))
    }
    $ghostsDir = Split-Path $DevkitRoot -Parent
    if ($ghostsDir -and (Split-Path $ghostsDir -Leaf) -eq 'ghost') {
        $candidates.Add(@('installed ghost folder', (Join-Path (Split-Path $ghostsDir -Parent) 'ssp.exe'), $false))
    }
    $associated = Get-SspPathFromNarAssociation
    if ($associated) { $candidates.Add(@('.nar file association', $associated, $false)) }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate[1] -PathType Leaf) {
            return [pscustomobject]@{ Path = (Resolve-Path -LiteralPath $candidate[1]).Path; Source = $candidate[0] }
        }
        if ($candidate[2]) { Write-Warning "ssp.exe from $($candidate[0]) does not exist: $($candidate[1])" }
    }
    return $null
}

# Returns the version of ssp.exe as major.minor.build (for example 2.8.94), or $null when it cannot be read.
function Get-DevkitSspVersion([string]$Path) {
    try {
        $info = (Get-Item -LiteralPath $Path).VersionInfo
        if ($info.FileMajorPart -gt 0) { return (New-Object System.Version($info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart)) }
    } catch { }
    return $null
}

# Quotes arguments for ProcessStartInfo.Arguments (MSVCRT rules).
function ConvertTo-DevkitArgumentString([string[]]$Arguments) {
    $parts = foreach ($arg in $Arguments) {
        if ($null -eq $arg) { continue }
        if ($arg -eq '' -or $arg -match '[\s"]') {
            $escaped = [regex]::Replace($arg, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
            $escaped = [regex]::Replace($escaped, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
            '"' + $escaped + '"'
        } else {
            $arg
        }
    }
    return ($parts -join ' ')
}

# Runs a program and captures stdout/stderr as UTF-8 text.
function Invoke-DevkitProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory,
        [int]$TimeoutSeconds = 120,
        # Text for the standard input, written as UTF-8 without BOM; the input is closed afterwards.
        [string]$InputText,
        # Environment variables that the program does not inherit.
        [string[]]$UnsetEnvironment = @()
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ConvertTo-DevkitArgumentString $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $PSBoundParameters.ContainsKey('InputText')
    $psi.StandardOutputEncoding = $DevkitUtf8
    $psi.StandardErrorEncoding = $DevkitUtf8
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    foreach ($name in $UnsetEnvironment) {
        if ($psi.EnvironmentVariables.ContainsKey($name)) { $psi.EnvironmentVariables.Remove($name) }
    }

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if ($psi.RedirectStandardInput) {
        # Write the bytes to the base stream: the StreamWriter of .NET Framework may add a BOM when it is closed.
        $bytes = $DevkitUtf8.GetBytes([string]$InputText)
        $stdin = $process.StandardInput.BaseStream
        try {
            $stdin.Write($bytes, 0, $bytes.Length)
            $stdin.Flush()
        } catch {
            # The program exited without reading the input; its output tells why.
        } finally {
            try { $stdin.Close() } catch { }
        }
    }
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try { $process.Kill() } catch { }
        $process.WaitForExit()
    }
    $exitCode = if ($timedOut) { -1 } else { $process.ExitCode }
    return [pscustomobject]@{
        ExitCode = $exitCode
        StdOut   = $stdoutTask.Result
        StdErr   = $stderrTask.Result
        TimedOut = $timedOut
    }
}

# Rewrites absolute paths under $Base into root-relative paths with forward slashes.
# SSP 2.8.94 or later adds places such as "shell\master\surfaces.txt:Line=12" to SERIKO messages (absolute with
# --offline-dump, relative to the ghost folder otherwise); their backslashes are turned into slashes as well.
function ConvertTo-DevkitRelativeText([string]$Text, [string]$Base = $DevkitRoot) {
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $pattern = '(?i)' + [regex]::Escape($Base.TrimEnd('\', '/')) + '[\\/]([^\s(),"]*)'
    $Text = [regex]::Replace($Text, $pattern, { param($m) $m.Groups[1].Value.Replace('\', '/') })
    return [regex]::Replace($Text, '[^\s(),"]+(?=:Line=\d)', { param($m) $m.Value.Replace('\', '/') })
}
