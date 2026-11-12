# Runs the Dawn of Kin headless GDScript test suite.
# Fails on non-zero exit code or any Godot ERROR, SCRIPT ERROR, or WARNING.

[CmdletBinding()]
param(
    [string]$Filter = "",
    [int]$TimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "godot.ps1")

$root = Get-ProjectRoot
$argsList = @("--headless", "--path", $root, "--script", "res://tests/framework/test_runner.gd")

if ($Filter -ne "") {
    $argsList += @("--", "--filter=$Filter")
}

$res = Invoke-Godot -Arguments $argsList -FailOnWarnings -TimeoutSeconds $TimeoutSeconds
$res.AllLines | ForEach-Object { Write-Host $_ }

if (-not $res.Success) {
    $exitCode = if ($res.ExitCode -ne 0) { $res.ExitCode } else { 1 }
    exit $exitCode
}

exit 0
