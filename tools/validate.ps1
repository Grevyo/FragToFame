<#
.SYNOPSIS
  Headless validation for Frag to Fame: import project, then run tests/run_tests.gd.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\validate.ps1 -Godot "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
  # or set $env:GODOT_BIN once and run without -Godot
#>
param(
    [string]$Godot = $env:GODOT_BIN
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot

if (-not $Godot) {
    Write-Error "Godot executable not specified. Pass -Godot <path> or set GODOT_BIN (use the *_console.exe build)."
    exit 2
}
if (-not (Test-Path $Godot)) {
    Write-Error "Godot executable not found: $Godot"
    exit 2
}

Write-Host "== Godot version ==" -ForegroundColor Cyan
& $Godot --version

Write-Host "== Headless import (parses all scripts and scenes) ==" -ForegroundColor Cyan
$importLog = & $Godot --headless --path $project --import 2>&1 | Out-String
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
