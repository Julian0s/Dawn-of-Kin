# Reproducible Godot 4.7.2 Interactive Showcase & Un-Vsynced A/B Benchmark for UI-0 R2.1 (Direction D2.1)
# Runs completely isolated via --script without altering any production gameplay files.
# Usage:
#   .\docs\design\ui-0-r2-1\godot_showcase\run_ui0_r2_1_showcase.ps1                (captures + A/B benchmark)
#   .\docs\design\ui-0-r2-1\godot_showcase\run_ui0_r2_1_showcase.ps1 -Interactive   (live interactive demo)

[CmdletBinding()]
param(
    [switch]$Interactive,
    [int]$TimeoutSeconds = 240
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
Set-Location $repoRoot
. ".\tools\godot.ps1"

$scriptPath = (Resolve-Path (Join-Path $PSScriptRoot "ui0_r2_1_d2_showcase.gd")).Path
Write-Host "=== Running UI-0 R2.1 D2 Godot Showcase ==="
Write-Host "Repo:        $repoRoot"
Write-Host "Script:      $scriptPath"
Write-Host "Interactive: $Interactive"

$imp = Invoke-Godot -Arguments @("--headless", "--path", $repoRoot, "--import") -TimeoutSeconds 90
if ($imp.ExitCode -ne 0) {
    throw "Godot --import failed with exit code $($imp.ExitCode)"
}

if ($Interactive) {
    $run = Invoke-Godot -Arguments @("--path", $repoRoot, "--windowed", "--resolution", "1280x720", "--script", $scriptPath, "--", "--interactive") -TimeoutSeconds 3600
    $run.AllLines | ForEach-Object { Write-Host $_ }
    exit $run.ExitCode
}

$run = Invoke-Godot -Arguments @("--path", $repoRoot, "--windowed", "--resolution", "640x360", "--script", $scriptPath) -TimeoutSeconds $TimeoutSeconds
$run.AllLines | ForEach-Object { Write-Host $_ }
if ($run.ExitCode -ne 0) {
    throw "Showcase failed with exit code $($run.ExitCode)"
}
Write-Host "=== UI-0 R2.1 D2 Showcase Complete ==="
