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

function Invoke-Godot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$FailOnWarnings
    )

    $godot = Get-GodotExecutable
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()

    try {
        # Quote arguments containing spaces for Start-Process on Windows.
        $quotedArgs = foreach ($arg in $Arguments) {
            if ($arg -match '\s' -and -not ($arg.StartsWith('"') -and $arg.EndsWith('"'))) {
                "`"$arg`""
            } else {
                $arg
            }
        }

        $proc = Start-Process -FilePath $godot `
            -ArgumentList $quotedArgs `
            -RedirectStandardOutput $tmpOut `
            -RedirectStandardError $tmpErr `
            -Wait `
            -PassThru `
            -NoNewWindow

        $stdoutLines = @()
        if (Test-Path $tmpOut) {
            $stdoutLines = @(Get-Content -Path $tmpOut -Encoding UTF8)
        }
        $stderrLines = @()
        if (Test-Path $tmpErr) {
            $stderrLines = @(Get-Content -Path $tmpErr -Encoding UTF8)
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

        return [PSCustomObject]@{
            ExitCode   = $proc.ExitCode
            Stdout     = $stdoutLines
            Stderr     = $stderrLines
            AllLines   = $allLines
            HasError   = $hasError
            HasWarning = $hasWarning
            Success    = ($proc.ExitCode -eq 0) -and (-not $hasError) -and (-not ($FailOnWarnings -and $hasWarning))
        }
    } finally {
        Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue
    }
}
