# Claude Code SessionStart hook (see .claude/settings.json).
# Runs tools/doctor.ps1. When a required or recommended item is missing, prints a short note with the fixes;
# Claude Code adds SessionStart stdout to the context, so Claude can offer to take care of them.
# Prints nothing when the environment is ready.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/common.ps1')
Initialize-DevkitConsole

try {
    $powershell = (Get-Process -Id $PID).Path
    $result = Invoke-DevkitProcess -FilePath $powershell -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $DevkitToolsDir 'doctor.ps1'), '-Json') -TimeoutSeconds 50
    $report = $result.StdOut | ConvertFrom-Json
} catch {
    exit 0
}

$missing = @($report.items | Where-Object { -not $_.ok -and $_.level -ne 'optional' })
if ($missing.Count -eq 0) { exit 0 }

$names = ($missing | ForEach-Object { "$($_.name) ($($_.level))" }) -join ', '
Write-Output "Ghost development kit: some items need attention: $names."
foreach ($item in $missing) { Write-Output "- $($item.name): $($item.fix)" }
Write-Output 'Before other work, offer to take care of them (setup and GHOST.md: getting-started skill; .devkit-new files: update-devkit skill; details: tools/doctor.ps1). Ask the user before installing any application.'
exit 0
