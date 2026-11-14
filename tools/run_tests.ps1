# Runs the Dawn of Kin headless GDScript test suite.
# Fails on non-zero exit code or any Godot ERROR, SCRIPT ERROR, or WARNING.
# Supports single-process execution (default) and -Segmented (isolated multi-batch execution).

[CmdletBinding()]
param(
    [string]$Filter = "",
    [int]$TimeoutSeconds = 120,
    [switch]$Segmented,
    [int]$GroupTimeoutSeconds = 120,
    [int]$MaxIntegrationPerGroup = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "godot.ps1")

$root = Get-ProjectRoot
$runnerScript = "res://tests/framework/test_runner.gd"

if (-not $Segmented) {
    $argsList = @("--headless", "--path", $root, "--script", $runnerScript)
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
}

if ($Filter -ne "") {
    Write-Error "-Filter cannot be combined with -Segmented when verifying full suite coverage; omit -Segmented for filtered runs."
    exit 1
}

$wallSw = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "=== [SEGMENTED RUN] Discovering test suites ===" -ForegroundColor Cyan
$discRes = Invoke-Godot -Arguments @("--headless", "--path", $root, "--script", $runnerScript, "--", "--discovery-only") -FailOnWarnings -TimeoutSeconds 60
if (-not $discRes.Success) {
    $discRes.AllLines | ForEach-Object { Write-Host $_ }
    exit (if ($discRes.ExitCode -ne 0) { $discRes.ExitCode } else { 1 })
}

$discovered = New-Object System.Collections.Generic.List[string]
foreach ($line in $discRes.AllLines) {
    if ($line -match '^DISCOVERED_SUITE\s+(res://\S+)$') {
        $discovered.Add($matches[1])
    }
}

if ($discovered.Count -eq 0) {
    Write-Error "Segmented runner discovered 0 suites."
    exit 1
}

$unitSuites = @($discovered | Where-Object { $_ -like "res://tests/unit/*" })
$otherSuites = @($discovered | Where-Object { $_ -notlike "res://tests/unit/*" })

$batches = New-Object System.Collections.Generic.List[object]
if ($unitSuites.Count -gt 0) {
    $batches.Add([PSCustomObject]@{ Name = "unit"; Suites = $unitSuites })
}

$chunkSize = [Math]::Max(1, $MaxIntegrationPerGroup)
for ($i = 0; $i -lt $otherSuites.Count; $i += $chunkSize) {
    $end = [Math]::Min($i + $chunkSize - 1, $otherSuites.Count - 1)
    $slice = @($otherSuites[$i..$end])
    $batchIdx = [int][Math]::Floor($i / $chunkSize) + 1
    $batches.Add([PSCustomObject]@{ Name = ("integration-{0:D2}" -f $batchIdx); Suites = $slice })
}

Write-Host ("Discovered {0} suites -> partitioned into {1} disjoint batches (unit={2}, other={3}, max_per_batch={4})." -f $discovered.Count, $batches.Count, $unitSuites.Count, $otherSuites.Count, $chunkSize)

$executedSet = New-Object System.Collections.Generic.HashSet[string]
$executedList = New-Object System.Collections.Generic.List[string]
$aggSuites = 0
$aggTests = 0
$aggPassed = 0
$aggFailed = 0
$aggSuiteErrors = 0
$aggAssertions = 0
$aggGodotElapsedMs = 0.0
$anyFailure = $false
$batchSummaries = New-Object System.Collections.Generic.List[string]

foreach ($batch in $batches) {
    $suitesArg = "--suites=" + ($batch.Suites -join ",")
    Write-Host ("`n--- [BATCH {0}] ({1} suites): {2} ---" -f $batch.Name, $batch.Suites.Count, ($batch.Suites -join ", ")) -ForegroundColor Yellow

    $batchRes = Invoke-Godot -Arguments @("--headless", "--path", $root, "--script", $runnerScript, "--", $suitesArg) -FailOnWarnings -TimeoutSeconds $GroupTimeoutSeconds
    $batchRes.AllLines | ForEach-Object { Write-Host $_ }

    foreach ($line in $batchRes.AllLines) {
        if ($line -match '^\[SUITE_DONE\]\s+(res://\S+)\s+\|') {
            $doneSuite = $matches[1]
            $executedList.Add($doneSuite)
            [void]$executedSet.Add($doneSuite)
        }
        elseif ($line -match '^Suites:\s*(\d+)\s*\|\s*Tests:\s*(\d+)\s*\|\s*Passed:\s*(\d+)\s*\|\s*Failed:\s*(\d+)\s*\|\s*SuiteErrors:\s*(\d+)\s*\|\s*Assertions:\s*(\d+)\s*\|\s*Elapsed:\s*([\d\.]+)\s*ms') {
            $aggSuites += [int]$matches[1]
            $aggTests += [int]$matches[2]
            $aggPassed += [int]$matches[3]
            $aggFailed += [int]$matches[4]
            $aggSuiteErrors += [int]$matches[5]
            $aggAssertions += [int]$matches[6]
            $aggGodotElapsedMs += [double]::Parse($matches[7], [System.Globalization.CultureInfo]::InvariantCulture)
        }
    }

    if (-not $batchRes.Success) {
        $anyFailure = $true
        $batchSummaries.Add("FAIL $($batch.Name) (exit=$($batchRes.ExitCode), timedOut=$($batchRes.TimedOut))")
    } else {
        $batchSummaries.Add("PASS $($batch.Name)")
    }
}

$wallSw.Stop()

# Verify bijection between discovered and executed suites (zero omissions, zero duplicates)
$missingSuites = @($discovered | Where-Object { -not $executedSet.Contains($_) })
$duplicateCount = $executedList.Count - $executedSet.Count
if ($missingSuites.Count -gt 0 -or $duplicateCount -ne 0 -or $aggSuites -ne $discovered.Count) {
    $anyFailure = $true
    Write-Error ("Coverage mismatch! Discovered=$($discovered.Count), Aggregated=$aggSuites, UniqueExecuted=$($executedSet.Count), Duplicates=$duplicateCount, Missing=$($missingSuites -join ', ')")
}

Write-Host ""
Write-Host "=== [SEGMENTED RUN] Aggregated Test Summary ===" -ForegroundColor Cyan
Write-Host ("Batches: {0} ({1})" -f $batches.Count, ($batchSummaries -join "; "))
Write-Host ("Suites: {0} | Tests: {1} | Passed: {2} | Failed: {3} | SuiteErrors: {4} | Assertions: {5} | SumGodotElapsed: {6:F1} ms | TotalWallElapsed: {7:F1} ms" -f `
    $aggSuites, $aggTests, $aggPassed, $aggFailed, $aggSuiteErrors, $aggAssertions, $aggGodotElapsedMs, $wallSw.Elapsed.TotalMilliseconds)
Write-Host ("Coverage Check: Discovered={0} | ExecutedUnique={1} | Duplicates={2} | Missing={3}" -f `
    $discovered.Count, $executedSet.Count, $duplicateCount, $missingSuites.Count)

if ($anyFailure -or $aggFailed -gt 0 -or $aggSuiteErrors -gt 0) {
    exit 1
}

exit 0
