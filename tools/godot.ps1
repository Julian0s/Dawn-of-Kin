# Helper functions to locate and invoke Godot 4.7.2 reliably on Windows.

Set-StrictMode -Version Latest

function Get-ProjectRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-GodotExecutable {
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) {
        return (Resolve-Path $env:GODOT_BIN).Path
    }

    $cmd = Get-Command "godot", "godot4", "Godot_v4.7.2-stable_win64.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and (Test-Path $cmd.Source)) {
        return $cmd.Source
    }

    $fallback = Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
    if (Test-Path $fallback) {
        return $fallback
    }

    throw "Godot executable not found. Set the GODOT_BIN environment variable to the Godot 4.7.2 executable path."
}

function Format-WindowsArgument {
    param([string]$Arg)
    if ($Arg -eq "") {
        return '""'
    }
    if ($Arg -match '[\s"]') {
        return '"' + ($Arg -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
    }
    return $Arg
}

function Invoke-Godot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$FailOnWarnings,

        [int]$TimeoutSeconds = 0
    )

    $godot = Get-GodotExecutable
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $godot
    $psi.Arguments = (($Arguments | ForEach-Object { Format-WindowsArgument $_ }) -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try {
        [void]$proc.Start()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()

        if ($TimeoutSeconds -gt 0) {
            $finished = $proc.WaitForExit($TimeoutSeconds * 1000)
            if (-not $finished) {
                try { $proc.Kill() } catch {}
                throw "Godot process timed out after $TimeoutSeconds seconds."
            }
        }

        # Parameterless WaitForExit ensures async stream readers flush and ExitCode is populated.
        $proc.WaitForExit()
        [void][System.Threading.Tasks.Task]::WaitAll(@($outTask, $errTask))

        $stdoutLines = @()
        if ($outTask.Result) {
            $stdoutLines = @($outTask.Result -split "`r?`n")
            if ($stdoutLines.Count -gt 0 -and $stdoutLines[-1] -eq "") {
                $stdoutLines = if ($stdoutLines.Count -gt 1) { $stdoutLines[0..($stdoutLines.Count - 2)] } else { @() }
            }
        }

        $stderrLines = @()
        if ($errTask.Result) {
            $stderrLines = @($errTask.Result -split "`r?`n")
            if ($stderrLines.Count -gt 0 -and $stderrLines[-1] -eq "") {
                $stderrLines = if ($stderrLines.Count -gt 1) { $stderrLines[0..($stderrLines.Count - 2)] } else { @() }
            }
        }

        $allLines = @($stdoutLines + $stderrLines)
        $hasError = $false
        $hasWarning = $false

        foreach ($line in $allLines) {
            if ($line -match '^(SCRIPT ERROR:|ERROR:|FATAL:|SHADER ERROR:)') {
                $hasError = $true
            } elseif ($line -match '^WARNING:') {
                $hasWarning = $true
            }
        }

        $exitCode = [int]$proc.ExitCode
        return [PSCustomObject]@{
            ExitCode   = $exitCode
            Stdout     = $stdoutLines
            Stderr     = $stderrLines
            AllLines   = $allLines
            HasError   = $hasError
            HasWarning = $hasWarning
            Success    = ($exitCode -eq 0) -and (-not $hasError) -and (-not ($FailOnWarnings -and $hasWarning))
        }
    } finally {
        $proc.Dispose()
    }
}
