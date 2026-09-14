<#
.SYNOPSIS
    Downloads the pinned development tools into tools/bin/ (not committed to git).
.DESCRIPTION
    Versions, URLs and SHA256 hashes are pinned in tools/tools.json.
    Also prints hints about the git submodule, Node.js (for the ukagaka-doc MCP server) and SSP.
    Exit codes: 0 = OK, 1 = a download failed.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup.ps1 -Tool tamac -Force
#>
[CmdletBinding()]
param(
    [string[]]$Tool,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-DevkitConsole

$manifest = Get-DevkitToolManifest
$names = @($manifest.PSObject.Properties.Name)
if ($Tool) {
    foreach ($name in $Tool) {
        if ($names -notcontains $name) { throw "Unknown tool '$name'. Available: $($names -join ', ')" }
    }
    $names = $Tool
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path $DevkitBinDir | Out-Null

$failed = 0
foreach ($name in $names) {
    $entry = $manifest.$name
    $exePath = Join-Path $DevkitBinDir $entry.exe
    if ((Test-Path -LiteralPath $exePath) -and -not $Force) {
        Write-Host "[skip] $name $($entry.version) is already installed: $exePath"
        continue
    }

    Write-Host "[download] $name $($entry.version) <- $($entry.url)"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('devkit-' + [guid]::NewGuid().ToString('N') + '-' + [IO.Path]::GetFileName($entry.url))
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $entry.url -OutFile $tmp
        $hash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
        if ($hash -ne $entry.sha256.ToUpperInvariant()) {
            throw "SHA256 mismatch (expected $($entry.sha256), got $hash)"
        }
        if ($entry.type -eq 'zip') {
            $dest = Join-Path $DevkitBinDir $entry.installDir
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
            Expand-Archive -LiteralPath $tmp -DestinationPath $dest
        } else {
            New-Item -ItemType Directory -Force -Path (Split-Path $exePath -Parent) | Out-Null
            Copy-Item -LiteralPath $tmp -Destination $exePath -Force
        }
        if (-not (Test-Path -LiteralPath $exePath)) { throw "$($entry.exe) was not found after installing" }
        Write-Host "[ok] $name -> $exePath"
    } catch {
        $failed++
        Write-Host "[error] $name : $($_.Exception.Message)"
        Write-Host "        If antivirus software removed the file, it may be a false positive; check the release page."
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    }
}

Write-Host ''
if (-not (Test-Path -LiteralPath (Join-Path $DevkitRoot 'ghost/master/dic/system/yaya_base/shiori3.dic'))) {
    Write-Host '[warn] ghost/master/dic/system is empty. In a git clone, run: git submodule update --init'
}

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $node) {
    Write-Host '[info] Node.js was not found. It is only needed for the ukagaka-doc MCP server (Node.js 20 or later).'
} else {
    $nodeVersion = (Invoke-DevkitProcess -FilePath $node.Source -Arguments @('--version') -TimeoutSeconds 30).StdOut.Trim()
    if ($nodeVersion -match '^v(\d+)\.' -and [int]$matches[1] -lt 20) {
        Write-Host "[warn] Node.js $nodeVersion is too old for the ukagaka-doc MCP server (needs 20 or later)."
    } else {
        Write-Host "[info] Node.js $nodeVersion"
    }
}

$ssp = Resolve-SspPath
if ($ssp) {
    Write-Host "[info] SSP: $($ssp.Path) (found via $($ssp.Source))"
} else {
    Write-Host '[info] SSP was not found. Shell checks and SSTP need it: set SSP_PATH or create tools/local.json (see tools/local.example.json).'
}

if ($failed -gt 0) { exit 1 }
exit 0
