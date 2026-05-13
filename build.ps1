# build.ps1 — Build Terraton Fan APK, save locally, and publish to GitHub Releases

$ProjectRoot = $PSScriptRoot
$AppDir      = Join-Path $ProjectRoot "terraton_fan_app"
$BuildsDir   = Join-Path $ProjectRoot "builds"
$Repo        = "austin207/Terraton-BLDC-Fan-BLE-Controller"
$ReleaseTag  = "latest"

# ── 0. Clear builds folder ───────────────────────────────────────────────────
if (Test-Path $BuildsDir) {
    Remove-Item (Join-Path $BuildsDir "*.apk") -Force
    Write-Host "Cleared old APKs from builds/" -ForegroundColor DarkGray
}

# ── 1. Regenerate launcher icons from assets/icon/icon.png ───────────────────
Write-Host "Regenerating launcher icons..." -ForegroundColor Cyan
Set-Location $AppDir
dart run flutter_launcher_icons
if ($LASTEXITCODE -ne 0) {
    Write-Host "Launcher icon generation failed." -ForegroundColor Red
    exit 1
}

# ── 2. Clean all caches ──────────────────────────────────────────────────────
Set-Location $AppDir

Write-Host "Running flutter clean..." -ForegroundColor Cyan
flutter clean
if ($LASTEXITCODE -ne 0) { Write-Host "flutter clean failed." -ForegroundColor Red; exit 1 }

# Gradle project cache — flutter clean covers this on 3.7+ but be explicit
$GradleCache = Join-Path $AppDir "android\.gradle"
if (Test-Path $GradleCache) {
    Remove-Item $GradleCache -Recurse -Force
    Write-Host "Cleared android/.gradle/" -ForegroundColor DarkGray
}

# Restore packages after clean wipes .dart_tool/
Write-Host "Running flutter pub get..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Host "flutter pub get failed." -ForegroundColor Red; exit 1 }

# Regenerate ObjectBox + Riverpod .g.dart files — stale generated code silently breaks builds
Write-Host "Regenerating ObjectBox / Riverpod code..." -ForegroundColor Cyan
dart run build_runner build --delete-conflicting-outputs
if ($LASTEXITCODE -ne 0) { Write-Host "build_runner failed." -ForegroundColor Red; exit 1 }

# ── 3. Build (split per ABI — ~20 MB each instead of ~80 MB fat APK) ─────────
Write-Host "Building Terraton Fan APKs (split-per-abi)..." -ForegroundColor Cyan

flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit 1
}

# arm64-v8a covers all modern Android phones and is the primary download.
# arm7 and x86_64 are also uploaded for older devices and emulators.
$ApkDir  = Join-Path $AppDir "build\app\outputs\flutter-apk"
$Arm64   = Join-Path $ApkDir "app-arm64-v8a-release.apk"
$Arm7    = Join-Path $ApkDir "app-armeabi-v7a-release.apk"
$X86     = Join-Path $ApkDir "app-x86_64-release.apk"

if (-not (Test-Path $Arm64)) {
    Write-Host "arm64 APK not found at: $Arm64" -ForegroundColor Red
    exit 1
}

# ── 4. Save timestamped copies locally ───────────────────────────────────────
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$Arm64Name  = "terraton-fan-arm64-$Timestamp.apk"
$Arm7Name   = "terraton-fan-arm7-$Timestamp.apk"
$X86Name    = "terraton-fan-x86_64-$Timestamp.apk"
$Arm64Local = Join-Path $BuildsDir $Arm64Name
$Arm7Local  = Join-Path $BuildsDir $Arm7Name
$X86Local   = Join-Path $BuildsDir $X86Name

Copy-Item $Arm64 $Arm64Local
Write-Host "Saved arm64 : $Arm64Local" -ForegroundColor Green
if (Test-Path $Arm7)  { Copy-Item $Arm7 $Arm7Local;  Write-Host "Saved arm7  : $Arm7Local"  -ForegroundColor Green }
if (Test-Path $X86)   { Copy-Item $X86  $X86Local;   Write-Host "Saved x86_64: $X86Local"   -ForegroundColor Green }

# ── 5. Publish to GitHub Releases (tag: latest) ───────────────────────────────
Write-Host ""
Write-Host "Publishing to GitHub Releases..." -ForegroundColor Cyan
Set-Location $ProjectRoot

# Delete existing 'latest' release and tag so we can replace it cleanly
gh release delete $ReleaseTag --repo $Repo --yes 2>$null
git tag -d $ReleaseTag 2>$null
git push origin --delete $ReleaseTag 2>$null

# Collect APKs to upload (arm64 always present; others if built)
$Assets = @($Arm64Local)
if (Test-Path $Arm7Local) { $Assets += $Arm7Local }
if (Test-Path $X86Local)  { $Assets += $X86Local  }

$BuildDate = Get-Date -Format "yyyy-MM-dd HH:mm"
$Notes = @"
Built on $BuildDate

Both QR scan and Bluetooth scan onboarding are included in every APK.

| APK | Architecture | Use for |
|-----|-------------|---------|
| terraton-fan-arm64-*.apk | arm64-v8a | All modern Android phones (recommended) |
| terraton-fan-arm7-*.apk  | armeabi-v7a | Older 32-bit Android phones |
| terraton-fan-x86_64-*.apk | x86_64 | Android emulators |
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
Write-Host "Recommended download (arm64): https://github.com/$Repo/releases/latest/download/$Arm64Name" -ForegroundColor Cyan
