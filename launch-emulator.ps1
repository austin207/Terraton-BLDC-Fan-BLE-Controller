# launch-emulator.ps1 — Launch the S24 Ultra emulator and optionally run the app.
#
# Usage:
#   .\launch-emulator.ps1          — start emulator (skip if already running)
#   .\launch-emulator.ps1 -Run     — start emulator then flutter run
#   .\launch-emulator.ps1 -RunOnly — flutter run on the already-running emulator

param(
    [switch]$Run,     # boot emulator then flutter run
    [switch]$RunOnly  # skip boot, just flutter run on whatever emulator is live
)

Set-Location $PSScriptRoot

function Get-EmulatorId {
    $out = flutter devices 2>&1 | Out-String
    if ($out -match 'emulator-(\d+)') { return "emulator-$($Matches[1])" }
    return $null
}

# ── RunOnly: emulator is already up, just flutter run ────────────────────────
if ($RunOnly) {
    $id = Get-EmulatorId
    if (-not $id) {
        Write-Host "No emulator found. Start one first (omit -RunOnly)." -ForegroundColor Red
        exit 1
    }
    Write-Host "Emulator detected: $id" -ForegroundColor Green
    Set-Location "$PSScriptRoot\terraton_fan_app"
    flutter run -d $id
    exit 0
}

# ── Boot emulator (skip if already running) ──────────────────────────────────
$existingId = Get-EmulatorId
if ($existingId) {
    Write-Host "Emulator already running: $existingId — skipping launch." -ForegroundColor Yellow
} else {
    Write-Host "Starting S24 Ultra emulator..." -ForegroundColor Cyan
    flutter emulators --launch S24_Ultra
}

# ── Optionally wait and run the app ──────────────────────────────────────────
if ($Run) {
    Write-Host "Waiting for emulator to boot..." -ForegroundColor Cyan

    $timeout = 90
    $elapsed = 0
    $deviceId = $null

    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds 3
        $elapsed += 3
        $deviceId = Get-EmulatorId
        if ($deviceId) { break }
    }

    if (-not $deviceId) {
        Write-Host "Emulator did not appear within $timeout s. Run manually:" -ForegroundColor Yellow
        Write-Host "  cd terraton_fan_app; flutter run -d emulator-5554" -ForegroundColor Gray
        exit 1
    }

    Write-Host "Emulator ready: $deviceId" -ForegroundColor Green
    Set-Location "$PSScriptRoot\terraton_fan_app"
    flutter run -d $deviceId
}
