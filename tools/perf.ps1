# Runs T1.10 performance benchmarks, RVO cost breakdown, and stress test in windowed/fullscreen modes.
# Never uses --fixed-fps. Consolidates consecutive runs via median.

[CmdletBinding()]
param(
    [ValidateSet("all", "benchmark", "rvo", "stress")]
    [string]$Mode = "all",
    [int]$Runs = 3,
    [double]$WarmupSec = 5.0,
    [double]$DurationSec = 30.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "godot.ps1")

$root = Get-ProjectRoot
$outDir = Join-Path $root "test_output\perf"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

function Get-Median {
    param([double[]]$Values)
    if ($Values.Count -eq 0) { return 0.0 }
    $sorted = @($Values | Sort-Object)
    $mid = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) {
        return [double]$sorted[$mid]
    }
    return ([double]$sorted[$mid - 1] + [double]$sorted[$mid]) / 2.0
}

$summary = [ordered]@{
    timestamp = (Get-Date).ToString("o")
    power_plan = (powercfg /getactivescheme | Out-String).Trim()
    benchmarks = @()
    rvo_breakdown = $null
    stress_test = $null
}

if ($Mode -eq "all" -or $Mode -eq "benchmark") {
    $profiles = @(
        @{ label = "1280x720"; args = @("--resolution", "1280x720"); user = @("--resolution=1280x720") },
        @{ label = "1920x1080"; args = @("--resolution", "1920x1080"); user = @("--resolution=1920x1080") },
        @{ label = "native"; args = @("--fullscreen"); user = @("--fullscreen") }
    )

    foreach ($prof in $profiles) {
        $runResults = @()
        for ($r = 1; $r -le $Runs; $r++) {
            $jsonRel = "test_output/perf/bench_$($prof.label)_run$r.json"
            $jsonAbs = Join-Path $root $jsonRel
            if (Test-Path $jsonAbs) { Remove-Item $jsonAbs -Force }

            Write-Host "=== Benchmark [$($prof.label)] Run $r/$Runs (warmup=${WarmupSec}s, record=${DurationSec}s) ==="
            $godotArgs = @("--path", $root) + $prof.args + @(
                "--script", "res://tests/perf/perf_benchmark.gd",
                "--"
            ) + $prof.user + @(
                "--warmup=$WarmupSec",
                "--duration=$DurationSec",
                "--out=$jsonRel"
            )

            $res = Invoke-Godot -Arguments $godotArgs -FailOnWarnings
            if (-not $res.Success) {
                $res.AllLines | ForEach-Object { Write-Host $_ }
                throw "Benchmark failed on $($prof.label) run $r"
            }

            $runResults += (Get-Content $jsonAbs -Raw | ConvertFrom-Json)
        }

        $consolidated = [ordered]@{
            profile = $prof.label
            runs = $Runs
            screen_size = $runResults[0].screen_size
            window_size = $runResults[0].window_size
            viewport_size = $runResults[0].viewport_size
            vsync_mode = $runResults[0].vsync_mode
            gpu_adapter = $runResults[0].gpu_adapter
            cpu_name = $runResults[0].cpu_name
            renderer = $runResults[0].renderer
            median_avg_fps = [Math]::Round((Get-Median ($runResults | ForEach-Object { [double]$_.avg_fps })), 2)
            median_p50_ms = [Math]::Round((Get-Median ($runResults | ForEach-Object { [double]$_.frametime_p50_ms })), 3)
            median_p95_ms = [Math]::Round((Get-Median ($runResults | ForEach-Object { [double]$_.frametime_p95_ms })), 3)
            median_p99_ms = [Math]::Round((Get-Median ($runResults | ForEach-Object { [double]$_.frametime_p99_ms })), 3)
            median_max_ms = [Math]::Round((Get-Median ($runResults | ForEach-Object { [double]$_.frametime_max_ms })), 3)
            worst_max_ms = [Math]::Round((($runResults | ForEach-Object { [double]$_.frametime_max_ms } | Measure-Object -Maximum).Maximum), 3)
            total_frames_over_100ms = (($runResults | ForEach-Object { [int]$_.frames_over_100ms } | Measure-Object -Sum).Sum)
            median_phys_ms = [Math]::Round((Get-Median ($runResults | ForEach-Object { [double]$_.phys_avg_ms })), 3)
            median_nav_ms = [Math]::Round((Get-Median ($runResults | ForEach-Object { [double]$_.nav_avg_ms })), 3)
            median_draw_calls = [Math]::Round((Get-Median ($runResults | ForEach-Object { [double]$_.draw_calls_avg })), 1)
            median_objects = [Math]::Round((Get-Median ($runResults | ForEach-Object { [double]$_.objects_avg })), 0)
            median_mem_mb = [Math]::Round((Get-Median ($runResults | ForEach-Object { [double]$_.memory_static_avg_mb })), 2)
            raw_runs = $runResults
        }
        $summary.benchmarks += $consolidated
        Write-Host ("  -> Median [$($prof.label)]: FPS=$($consolidated.median_avg_fps) | p50=$($consolidated.median_p50_ms)ms | p95=$($consolidated.median_p95_ms)ms | p99=$($consolidated.median_p99_ms)ms | max=$($consolidated.median_max_ms)ms (worst=$($consolidated.worst_max_ms)ms) | >100ms=$($consolidated.total_frames_over_100ms)")
    }
}

if ($Mode -eq "all" -or $Mode -eq "rvo") {
    $rvoRel = "test_output/perf/rvo_breakdown.json"
    $rvoAbs = Join-Path $root $rvoRel
    if (Test-Path $rvoAbs) { Remove-Item $rvoAbs -Force }
    Write-Host "=== Running Controlled RVO Cost Breakdown ==="
    $rvoArgs = @("--path", $root, "--resolution", "1280x720", "--script", "res://tests/perf/rvo_cost_breakdown.gd", "--", "--out=$rvoRel")
    $res = Invoke-Godot -Arguments $rvoArgs -FailOnWarnings
    if (-not $res.Success) {
        $res.AllLines | ForEach-Object { Write-Host $_ }
        throw "RVO breakdown failed"
    }
    $summary.rvo_breakdown = (Get-Content $rvoAbs -Raw | ConvertFrom-Json)
}

if ($Mode -eq "all" -or $Mode -eq "stress") {
    $stressRel = "test_output/perf/stress_results.json"
    $stressAbs = Join-Path $root $stressRel
    if (Test-Path $stressAbs) { Remove-Item $stressAbs -Force }
    Write-Host "=== Running Informative RVO Stress Test (2, 10, 25, 50 units) ==="
    $stressArgs = @("--path", $root, "--resolution", "1280x720", "--script", "res://tests/perf/rvo_stress_test.gd", "--", "--out=$stressRel")
    $res = Invoke-Godot -Arguments $stressArgs -FailOnWarnings
    if (-not $res.Success) {
        $res.AllLines | ForEach-Object { Write-Host $_ }
        throw "Stress test failed"
    }
    $summary.stress_test = (Get-Content $stressAbs -Raw | ConvertFrom-Json)
}

$summaryPath = Join-Path $outDir "perf_summary.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -Path $summaryPath -Encoding UTF8
Write-Host "Perf summary saved to $summaryPath"
exit 0
