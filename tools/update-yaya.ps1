<#
.SYNOPSIS
    Updates ghost/master/yaya.dll from a YAYA release and verifies it with check-dic.
.DESCRIPTION
    Downloads yaya.zip from https://github.com/YAYA-shiori/yaya-shiori/releases (latest, or -Tag).
    If the dictionary check fails with the new DLL, the previous DLL is restored.
    Exit codes: 0 = updated / already up to date / dry run, 1 = failed.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-yaya.ps1 -DryRun
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-yaya.ps1 -Tag Tc573-6
#>
[CmdletBinding()]
param(
    [string]$Tag,
    [string]$GhostDir,
    [switch]$DryRun,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
Initialize-DevkitConsole
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $GhostDir) { $GhostDir = Join-Path $DevkitRoot 'ghost/master' }
$GhostDir = (Resolve-DevkitFullPath $GhostDir).TrimEnd('\', '/')
$dll = Join-Path $GhostDir 'yaya.dll'

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$api = 'https://api.github.com/repos/YAYA-shiori/yaya-shiori/releases/latest'
if ($Tag) { $api = 'https://api.github.com/repos/YAYA-shiori/yaya-shiori/releases/tags/' + [uri]::EscapeDataString($Tag) }
$release = Invoke-RestMethod -UseBasicParsing -Uri $api -Headers @{ 'User-Agent' = 'ghost-devkit'; 'Accept' = 'application/vnd.github+json' }
$asset = @($release.assets | Where-Object { $_.name -eq 'yaya.zip' }) | Select-Object -First 1
if (-not $asset) {
    Write-Host "update-yaya: yaya.zip was not found in release $($release.tag_name)"
    exit 1
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('devkit-yaya-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$exitCode = 0
try {
    $zipPath = Join-Path $work 'yaya.zip'
    Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $zipPath
    $newDll = Join-Path $work 'yaya.dll'
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entry = @($zip.Entries | Where-Object { $_.Name -eq 'yaya.dll' }) | Select-Object -First 1
        if ($entry) { [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $newDll) }
    } finally {
        $zip.Dispose()
    }
    if (-not (Test-Path -LiteralPath $newDll)) { throw 'yaya.dll is not in yaya.zip' }

    $hasOld = Test-Path -LiteralPath $dll
    $oldVersion = if ($hasOld) { (Get-Item -LiteralPath $dll).VersionInfo.FileVersion } else { '(none)' }
    $oldHash = if ($hasOld) { (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash } else { '' }
    $newVersion = (Get-Item -LiteralPath $newDll).VersionInfo.FileVersion
    $newHash = (Get-FileHash -LiteralPath $newDll -Algorithm SHA256).Hash
    Write-Host "current : $oldVersion"
    Write-Host "release : $($release.tag_name) (file version $newVersion)"
    Write-Host "notes   : $($release.html_url)"

    if ($oldHash -eq $newHash -and -not $Force) {
        Write-Host 'update-yaya: already up to date'
    } elseif ($DryRun) {
        Write-Host 'update-yaya: dry run, nothing changed'
    } else {
        $backup = Join-Path $work 'yaya.dll.old'
        if ($hasOld) { Copy-Item -LiteralPath $dll -Destination $backup }
        $replaced = $true
        try {
            Copy-Item -LiteralPath $newDll -Destination $dll -Force
        } catch {
            $replaced = $false
            Write-Host "update-yaya: could not replace yaya.dll ($($_.Exception.Message)). If SSP is running this ghost, close the ghost and retry."
            $exitCode = 1
        }
        if ($replaced) {
            $powershell = (Get-Process -Id $PID).Path
            $ErrorActionPreference = 'Continue'
            & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check-dic.ps1') -GhostDir $GhostDir
            $checkCode = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            if ($checkCode -eq 1) {
                if ($hasOld) { Copy-Item -LiteralPath $backup -Destination $dll -Force }
                Write-Host "update-yaya: the dictionary check failed with the new yaya.dll; restored $oldVersion"
                $exitCode = 1
            } else {
                if ($checkCode -eq 3) { Write-Host 'update-yaya: WARNING - tamac.exe is not installed, so the new yaya.dll was not verified' }
                Write-Host "update-yaya: updated yaya.dll $oldVersion -> $newVersion ($($release.tag_name))"
            }
        }
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
exit $exitCode
