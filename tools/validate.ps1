<#
.SYNOPSIS
  Headless validation for Frag to Fame: import project, then run tests/run_tests.gd.
.DESCRIPTION
  Godot is located in this order:
    1. -Godot <path>
    2. $env:GODOT_BIN
    3. godot / godot4 / Godot_v4.7.2-stable_*_console on PATH
    4. Known local installs, then a shallow search of C:\GrevCo and common install folders
       for Godot_v4.7.2-stable*_console.exe
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\validate.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\validate.ps1 -Godot "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
#>
param(
    [string]$Godot = $env:GODOT_BIN
)

$project = Split-Path -Parent $PSScriptRoot
$requiredVersion = '4.7.2.stable'

function Find-Godot {
    foreach ($name in @('godot', 'godot4', 'Godot_v4.7.2-stable_win64_console', 'Godot_v4.7.2-stable_mono_win64_console')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }

    $known = @(
        'C:\GrevCo\PokeArkova\Tools\Godot\Editor\Godot_v4.7.2-stable_mono_win64_console.exe'
    )
    foreach ($path in $known) {
        if (Test-Path $path) { return $path }
    }

    $roots = @('C:\GrevCo', "$env:LOCALAPPDATA\Programs", "$env:ProgramFiles", "$env:USERPROFILE\Downloads",
               "$env:USERPROFILE\Desktop", 'C:\Godot', 'C:\Tools')
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $hit = Get-ChildItem -Path $root -Filter 'Godot_v4.7.2-stable*_console.exe' -Recurse -Depth 5 `
                   -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

if (-not $Godot) {
    $Godot = Find-Godot
}
if (-not $Godot) {
    Write-Host "Could not find Godot 4.7.2." -ForegroundColor Red
    Write-Host "Pass -Godot <path> or set GODOT_BIN to the *_console.exe build, e.g.:" -ForegroundColor Red
    Write-Host '  $env:GODOT_BIN = "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"' -ForegroundColor Yellow
    exit 2
}
if (-not (Test-Path $Godot)) {
    Write-Host "Godot executable not found: $Godot" -ForegroundColor Red
    exit 2
}

Write-Host "== Godot: $Godot ==" -ForegroundColor Cyan
$version = (& $Godot --version | Out-String).Trim()
Write-Host $version
if ($version -notlike "$requiredVersion*") {
    Write-Host "WARNING: expected Godot $requiredVersion, found '$version'." -ForegroundColor Yellow
}

Write-Host "== Headless import (parses all scripts and scenes) ==" -ForegroundColor Cyan
# Native stderr is merged into the log; don't let PowerShell treat it as a terminating error.
$importLog = & $Godot --headless --path $project --import 2>&1 | ForEach-Object { "$_" } | Out-String
Write-Host $importLog
$importErrors = ($importLog -split "`n") | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load' }
if ($importErrors) {
    Write-Host "Import reported errors:" -ForegroundColor Red
    $importErrors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

Write-Host "== Headless tests ==" -ForegroundColor Cyan
& $Godot --headless --path $project --script res://tests/run_tests.gd
$testExit = $LASTEXITCODE
if ($testExit -ne 0) {
    Write-Host "Tests FAILED (exit $testExit)" -ForegroundColor Red
    exit $testExit
}
Write-Host "All validation steps passed." -ForegroundColor Green
exit 0
