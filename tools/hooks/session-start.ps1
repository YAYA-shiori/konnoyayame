# Claude Code SessionStart hook (see .claude/settings.json).
# Runs tools/doctor.ps1. When a required or recommended item is missing, prints a short note;
# Claude Code adds SessionStart stdout to the context, so Claude can offer to do the setup.
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
Write-Output "Ghost development kit: the environment is not fully set up. Missing: $names."
Write-Output 'Before other work, offer to set it up with the getting-started skill (details and fixes: tools/doctor.ps1). Ask the user before installing any application.'
exit 0
