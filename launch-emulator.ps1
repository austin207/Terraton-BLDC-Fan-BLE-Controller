# launch-emulator.ps1 - Launch an Android emulator and optionally run the app.
#
# Usage:
#   .\launch-emulator.ps1                        - start S24_Ultra (skip if already running)
#   .\launch-emulator.ps1 -Run                   - start emulator then flutter run
#   .\launch-emulator.ps1 -RunOnly               - flutter run on the already-running emulator
#   .\launch-emulator.ps1 -Kill                  - stop the running emulator
#   .\launch-emulator.ps1 -Avd Medium_Phone_API_36.0 -Run  - use a different AVD
#
# Flags:
#   -Run      boot emulator, wait for it to be ready, then flutter run
#   -RunOnly  skip boot; flutter run on whatever emulator is already live
#   -Kill     terminate the running emulator via adb emu kill
#   -Avd      AVD name to launch (default: S24_Ultra)
#   -Release  flutter run --release instead of --debug
#
# NOTE: flutter run always passes --no-enable-impeller so the emulator's
#       software GPU does not trigger the Impeller OpenGLES crash.

param(
    [switch]$Run,
    [switch]$RunOnly,
    [switch]$Kill,
    [switch]$Release,
    [string]$Avd = 'S24_Ultra'
)

Set-Location $PSScriptRoot

# ── Helpers ───────────────────────────────────────────────────────────────────

function Get-EmulatorId {
    $out = flutter devices 2>&1 | Out-String
    if ($out -match 'emulator-(\d+)') { return "emulator-$($Matches[1])" }
    return $null
}

function Invoke-FlutterRun {
    param([string]$DeviceId)
    $mode = if ($Release) { '--release' } else { '--debug' }
    Write-Host "Running app on $DeviceId ($mode, Impeller disabled)..." -ForegroundColor Cyan
    Set-Location (Join-Path $PSScriptRoot 'terraton_fan_app')
    # --no-enable-impeller prevents the OpenGLES crash on emulated GPU hardware
    flutter run -d $DeviceId $mode --no-enable-impeller
}

# ── Kill ──────────────────────────────────────────────────────────────────────

if ($Kill) {
    $id = Get-EmulatorId
    if (-not $id) {
        Write-Host 'No running emulator found.' -ForegroundColor Yellow
        exit 0
    }
    Write-Host "Stopping emulator $id ..." -ForegroundColor Yellow
    & adb -s $id emu kill 2>&1 | Out-Null
    Write-Host 'Emulator stopped.' -ForegroundColor Green
    exit 0
}

# ── RunOnly ───────────────────────────────────────────────────────────────────

if ($RunOnly) {
    $id = Get-EmulatorId
    if (-not $id) {
        Write-Host 'No emulator found. Start one first (omit -RunOnly).' -ForegroundColor Red
        exit 1
    }
    Write-Host "Emulator detected: $id" -ForegroundColor Green
    Invoke-FlutterRun -DeviceId $id
    exit 0
}

# ── Boot emulator (skip if already running) ───────────────────────────────────

$existingId = Get-EmulatorId
if ($existingId) {
    Write-Host "Emulator already running: $existingId - skipping launch." -ForegroundColor Yellow
} else {
    Write-Host "Starting AVD: $Avd ..." -ForegroundColor Cyan
    flutter emulators --launch $Avd
}

# ── Optionally wait for boot then run the app ─────────────────────────────────

if ($Run) {
    Write-Host 'Waiting for emulator to boot (up to 120 s)...' -ForegroundColor Cyan

    $timeout = 120
    $elapsed = 0
    $deviceId = $null

    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds 3
        $elapsed += 3
        $deviceId = Get-EmulatorId
        if ($deviceId) { break }
    }

    if (-not $deviceId) {
        Write-Host "Emulator did not appear within $timeout s." -ForegroundColor Red
        Write-Host 'Run manually once it boots:' -ForegroundColor Gray
        Write-Host "  .\launch-emulator.ps1 -RunOnly" -ForegroundColor Gray
        exit 1
    }

    # Extra pause — device appears before the system is fully ready
    Write-Host "Emulator ready: $deviceId - waiting 5 s for system settle..." -ForegroundColor Green
    Start-Sleep -Seconds 5

    Invoke-FlutterRun -DeviceId $deviceId
}
