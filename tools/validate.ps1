# Validates project import, GDScript syntax/types, and headless startup.
# Treats any Godot ERROR, SCRIPT ERROR, or WARNING as a failure.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "godot.ps1")

$root = Get-ProjectRoot
Write-Host "=== Dawn of Kin Validation ===" -ForegroundColor Cyan
Write-Host "Project root: $root"
Write-Host "Godot binary: $(Get-GodotExecutable)"

# 1. Headless import
Write-Host "`n[1/3] Running headless import..." -ForegroundColor Yellow
$importRes = Invoke-Godot -Arguments @("--headless", "--path", $root, "--import") -FailOnWarnings
$importRes.AllLines | ForEach-Object { Write-Host $_ }
if (-not $importRes.Success) {
    Write-Error "Headless import failed (Exit=$($importRes.ExitCode), HasError=$($importRes.HasError), HasWarning=$($importRes.HasWarning))."
    exit 1
}

# 2. Static check of all GDScript files under src/ and tests/
Write-Host "`n[2/3] Checking GDScript files (--check-only)..." -ForegroundColor Yellow
$scriptDirs = @("src", "tests") | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path $_ }
$gdFiles = @()
foreach ($dir in $scriptDirs) {
    $gdFiles += Get-ChildItem -Path $dir -Recurse -Filter "*.gd" | Sort-Object FullName
}

if ($gdFiles.Count -eq 0) {
    Write-Error "No .gd scripts found to validate under src/ or tests/."
    exit 1
}

foreach ($file in $gdFiles) {
    $rel = $file.FullName.Substring($root.Length + 1).Replace("\", "/")
    $resPath = "res://$rel"
    Write-Host "  Checking $resPath"
    $checkRes = Invoke-Godot -Arguments @("--headless", "--path", $root, "--check-only", "--script", $resPath) -FailOnWarnings
    if ($checkRes.Stderr.Count -gt 0) {
        $checkRes.Stderr | ForEach-Object { Write-Host $_ }
    }
    if (-not $checkRes.Success) {
        Write-Error "Script check failed for $resPath (Exit=$($checkRes.ExitCode), HasError=$($checkRes.HasError), HasWarning=$($checkRes.HasWarning))."
        exit 1
    }
}

# 3. Headless main scene boot smoke check
Write-Host "`n[3/3] Running headless main scene startup check (--quit-after 3)..." -ForegroundColor Yellow
$bootRes = Invoke-Godot -Arguments @("--headless", "--path", $root, "--quit-after", "3") -FailOnWarnings
$bootRes.AllLines | ForEach-Object { Write-Host $_ }
if (-not $bootRes.Success) {
    Write-Error "Headless startup check failed (Exit=$($bootRes.ExitCode), HasError=$($bootRes.HasError), HasWarning=$($bootRes.HasWarning))."
    exit 1
}

Write-Host "`nValidation PASSED (0 errors, 0 warnings, $($gdFiles.Count) scripts checked)." -ForegroundColor Green
exit 0
