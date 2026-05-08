# build.ps1 — Build Terraton Fan APK, save locally, and publish to GitHub Releases

$ProjectRoot = $PSScriptRoot
$AppDir      = Join-Path $ProjectRoot "terraton_fan_app"
$BuildsDir   = Join-Path $ProjectRoot "builds"
$Repo        = "austin207/Terraton-BLDC-Fan-BLE-Controller"
$ReleaseTag  = "latest"

# ── Helper: build one variant and copy APKs to $BuildsDir ────────────────────
function Build-Variant {
    param(
        [string]$Variant,     # "ble" or "qr"
        [string]$ExtraFlags   # e.g. "--dart-define=BLE_SCAN=true" or ""
    )

    Write-Host ""
    Write-Host "Building $Variant variant ($ExtraFlags)..." -ForegroundColor Cyan
    Set-Location $AppDir

    $cmd = "flutter build apk --release --split-per-abi $ExtraFlags".Trim()
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "$Variant build failed." -ForegroundColor Red
        exit 1
    }

    $ApkDir = Join-Path $AppDir "build\app\outputs\flutter-apk"
    $Arm64  = Join-Path $ApkDir "app-arm64-v8a-release.apk"
    $Arm7   = Join-Path $ApkDir "app-armeabi-v7a-release.apk"
    $X86    = Join-Path $ApkDir "app-x86_64-release.apk"

    if (-not (Test-Path $Arm64)) {
        Write-Host "arm64 APK not found at: $Arm64" -ForegroundColor Red
        exit 1
    }

    $ts       = Get-Date -Format "yyyyMMdd_HHmmss"
    $names    = @{}
    $locals   = @{}

    $names["arm64"] = "terraton-fan-$Variant-arm64-$ts.apk"
    $locals["arm64"] = Join-Path $BuildsDir $names["arm64"]
    Copy-Item $Arm64 $locals["arm64"]
    Write-Host "  Saved arm64  : $($locals['arm64'])" -ForegroundColor Green

    if (Test-Path $Arm7) {
        $names["arm7"]  = "terraton-fan-$Variant-arm7-$ts.apk"
        $locals["arm7"] = Join-Path $BuildsDir $names["arm7"]
        Copy-Item $Arm7 $locals["arm7"]
        Write-Host "  Saved arm7   : $($locals['arm7'])" -ForegroundColor Green
    }
    if (Test-Path $X86) {
        $names["x86"]  = "terraton-fan-$Variant-x86_64-$ts.apk"
        $locals["x86"] = Join-Path $BuildsDir $names["x86"]
        Copy-Item $X86 $locals["x86"]
        Write-Host "  Saved x86_64 : $($locals['x86'])" -ForegroundColor Green
    }

    return $locals
}

# ── 1. Build both variants ────────────────────────────────────────────────────
$QrApks  = Build-Variant -Variant "qr"  -ExtraFlags ""
$BleApks = Build-Variant -Variant "ble" -ExtraFlags "--dart-define=BLE_SCAN=true"

# ── 2. Publish to GitHub Releases (tag: latest) ───────────────────────────────
Write-Host ""
Write-Host "Publishing to GitHub Releases..." -ForegroundColor Cyan
Set-Location $ProjectRoot

gh release delete $ReleaseTag --repo $Repo --yes 2>$null
git tag -d $ReleaseTag 2>$null
git push origin --delete $ReleaseTag 2>$null

$Assets = @()
foreach ($v in @($BleApks, $QrApks)) {
    foreach ($k in @("arm64","arm7","x86")) {
        if ($v.ContainsKey($k)) { $Assets += $v[$k] }
    }
}

$BuildDate = Get-Date -Format "yyyy-MM-dd HH:mm"
$Notes = @"
Built on $BuildDate

## BLE Scan variant (`-ble-` in filename)
Onboarding: select fan from a Bluetooth scan list.

## QR Scan variant (`-qr-` in filename)
Onboarding: scan QR code on fan packaging.

| APK suffix | Architecture | Use for |
|------------|-------------|---------|
| arm64 | arm64-v8a | All modern Android phones **(recommended)** |
| arm7  | armeabi-v7a | Older 32-bit Android phones |
| x86_64 | x86_64 | Android emulators |
"@

gh release create $ReleaseTag @Assets `
    --repo $Repo `
    --title "Latest Build ($BuildDate)" `
    --notes $Notes `
    --latest

if ($LASTEXITCODE -ne 0) {
    Write-Host "GitHub release upload failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host "BLE arm64 (recommended): https://github.com/$Repo/releases/latest/download/$($BleApks['arm64'] | Split-Path -Leaf)" -ForegroundColor Cyan
Write-Host "QR  arm64             : https://github.com/$Repo/releases/latest/download/$($QrApks['arm64']  | Split-Path -Leaf)" -ForegroundColor Cyan
