# Launches Dawn of Kin in windowed mode using the resolved Godot 4.7.2 binary.

[CmdletBinding()]
param(
    [string]$Resolution = "1280x720",
    [int]$FixedFps = 0,
    [int]$QuitAfter = 0,
    [string]$LogFile = "",
    [switch]$DebugNavigation,
    [switch]$DebugCollisions,
    [switch]$FailOnWarnings,
    [string[]]$ExtraArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "godot.ps1")

$root = Get-ProjectRoot
$argsList = @("--path", $root, "--resolution", $Resolution)

if ($FixedFps -gt 0) {
    $argsList += @("--fixed-fps", $FixedFps.ToString())
}
if ($QuitAfter -gt 0) {
    $argsList += @("--quit-after", $QuitAfter.ToString())
}
if ($LogFile -ne "") {
    $argsList += @("--log-file", $LogFile)
}
if ($DebugNavigation) {
    $argsList += "--debug-navigation"
}
if ($DebugCollisions) {
    $argsList += "--debug-collisions"
}
if ($ExtraArgs.Count -gt 0) {
    $argsList += $ExtraArgs
}

$res = Invoke-Godot -Arguments $argsList -FailOnWarnings:$FailOnWarnings
$res.AllLines | ForEach-Object { Write-Host $_ }

if (-not $res.Success) {
    exit $(if ($res.ExitCode -ne 0) { $res.ExitCode } else { 1 })
}
exit 0
