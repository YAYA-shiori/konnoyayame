# Shared helpers for the development kit scripts in tools/.
# Dot-source it from a script: . (Join-Path $PSScriptRoot 'lib/common.ps1')
# Keep every tools/*.ps1 file ASCII-only and compatible with Windows PowerShell 5.1.

$DevkitRoot = [IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..') '..')).TrimEnd('\', '/')
$DevkitToolsDir = Join-Path $DevkitRoot 'tools'
$DevkitBinDir = Join-Path $DevkitToolsDir 'bin'
$DevkitUtf8 = New-Object System.Text.UTF8Encoding($false)
# SSP version that the kit is written for: GetStatus, Option: strict, SERIKO error places and --dump-error-log exit codes.
$DevkitSspRecommendedVersion = New-Object System.Version(2, 8, 94)

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
        [int]$TimeoutSeconds = 120
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ConvertTo-DevkitArgumentString $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $DevkitUtf8
    $psi.StandardErrorEncoding = $DevkitUtf8
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
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
