# build.ps1 — Build Terraton Fan APK, save locally, and publish to GitHub Releases

$ProjectRoot = $PSScriptRoot
$AppDir      = Join-Path $ProjectRoot "terraton_fan_app"
$BuildsDir   = Join-Path $ProjectRoot "builds"
$Repo        = "austin207/Terraton-BLDC-Fan-BLE-Controller"
$ReleaseTag  = "latest"

# ── Load secrets from secrets.env (gitignored) ───────────────────────────────
$SecretsFile = Join-Path $ProjectRoot "secrets.env"
$UploadApiKey = ''
if (Test-Path $SecretsFile) {
    Get-Content $SecretsFile | ForEach-Object {
        if ($_ -match '^\s*UPLOAD_API_KEY\s*=\s*(.+)$') {
            $UploadApiKey = $Matches[1].Trim()
        }
    }
    if ($UploadApiKey) {
        Write-Host "Loaded UPLOAD_API_KEY from secrets.env" -ForegroundColor DarkGray
    }
} else {
    Write-Host "WARNING: secrets.env not found -- UPLOAD_API_KEY will be empty. Copy secrets.env.template to secrets.env and fill in the values." -ForegroundColor Yellow
}

# ── Version bump ─────────────────────────────────────────────────────────────
$PubspecPath = Join-Path $AppDir "pubspec.yaml"
$PubspecRaw  = [System.IO.File]::ReadAllText($PubspecPath, [System.Text.Encoding]::UTF8)
if ($PubspecRaw -match 'version:\s+(\d+)\.(\d+)\.(\d+)\+(\d+)') {
    $vMaj = [int]$Matches[1]; $vMin = [int]$Matches[2]
    $vPat = [int]$Matches[3]; $vBld = [int]$Matches[4]
} else {
    Write-Host "ERROR: Could not parse version from pubspec.yaml (expected format: x.y.z+N)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Current version: $vMaj.$vMin.$vPat+$vBld" -ForegroundColor Yellow
Write-Host "  [P]atch  ->  $vMaj.$vMin.$($vPat + 1)+$($vBld + 1)   (default - small fixes / tweaks)"     -ForegroundColor DarkGray
Write-Host "  mi[N]or  ->  $vMaj.$($vMin + 1).0+$($vBld + 1)   (new features, backwards-compatible)"      -ForegroundColor DarkGray
Write-Host "  ma[J]or  ->  $($vMaj + 1).0.0+$($vBld + 1)   (breaking changes / landmark release)"         -ForegroundColor DarkGray
Write-Host "  [S]kip   ->  keep $vMaj.$vMin.$vPat+$vBld  (rebuild without bumping)"                        -ForegroundColor DarkGray
Write-Host ""
$bumpChoice = Read-Host "Bump type [P/N/J/S]"
if ([string]::IsNullOrEmpty($bumpChoice)) { $bumpChoice = 'P' }

# ── Variant selection ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Which variant(s) to build?" -ForegroundColor Yellow
Write-Host "  [T]ester  - all features + OTA updates (for your client's testing)" -ForegroundColor DarkGray
Write-Host "  [C]lient  - fans only, no OTA updates  (for end users)"             -ForegroundColor DarkGray
Write-Host "  [B]oth    - build Tester and Client     (default)"                  -ForegroundColor DarkGray
Write-Host ""
$variantChoice = Read-Host "Variant [T/C/B]"
if ([string]::IsNullOrEmpty($variantChoice)) { $variantChoice = 'B' }
$variantChoice = $variantChoice.Trim().ToUpper()
$buildTester = $variantChoice -eq 'T' -or $variantChoice -eq 'B'
$buildClient = $variantChoice -eq 'C' -or $variantChoice -eq 'B'

switch ($bumpChoice.Trim().ToUpper()) {
    'P' { $vPat++;                          $vBld++ }
    'N' { $vMin++; $vPat = 0;              $vBld++ }
    'J' { $vMaj++; $vMin = 0; $vPat = 0;  $vBld++ }
    'S' { <# no change #> }
    default { Write-Host "Unknown input - defaulting to Patch." -ForegroundColor Yellow; $vPat++; $vBld++ }
}

$SemVer     = "$vMaj.$vMin.$vPat"
$BuildNum   = $vBld
$NewVersion = "$SemVer+$BuildNum"

if ($bumpChoice.Trim().ToUpper() -ne 'S') {
    # Replace version line; '${1}' is the regex back-reference for the captured prefix
    $replacement = '${1}' + $NewVersion
    $PubspecRaw  = $PubspecRaw -replace '(?m)^(version:\s+)\d+\.\d+\.\d+\+\d+', $replacement
    $enc = New-Object System.Text.UTF8Encoding($false)   # UTF-8 without BOM
    [System.IO.File]::WriteAllText($PubspecPath, $PubspecRaw, $enc)
    Write-Host "Version bumped  ->  $NewVersion" -ForegroundColor Green
} else {
    Write-Host "Keeping version $NewVersion" -ForegroundColor DarkGray
}
Write-Host ""

# ── 0. Clear builds folder ───────────────────────────────────────────────────
if (Test-Path $BuildsDir) {
    Remove-Item (Join-Path $BuildsDir "*.apk") -Force
    Write-Host "Cleared old APKs from builds/" -ForegroundColor DarkGray
}

# ── 1. Clean all caches ──────────────────────────────────────────────────────
Set-Location $AppDir

# Kill leftover flutter build processes (Dart VMs, Gradle daemons, ADB)
Write-Host "Killing leftover build processes..." -ForegroundColor DarkGray
@('dart', 'java', 'flutter', 'adb') | ForEach-Object {
    Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 1

# Stop OneDrive sync so it doesn't hold file locks during flutter clean / build
Write-Host "Pausing OneDrive sync..." -ForegroundColor DarkGray
Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

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

# ── 3. Run test suite ────────────────────────────────────────────────────────
Write-Host "Running Flutter test suite..." -ForegroundColor Cyan
flutter test --no-pub
if ($LASTEXITCODE -ne 0) {
    Write-Host "Tests failed -- aborting build. Fix failing tests before releasing." -ForegroundColor Red
    exit 1
}
Write-Host "All tests passed." -ForegroundColor Green

# ── 4. Build variant(s) (split per ABI — ~20 MB each instead of ~80 MB fat APK)
$ApkDir = Join-Path $AppDir "build\app\outputs\flutter-apk"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# These fixed-name copies are what GitHub Releases serves for OTA downloads.
# Only the tester variant uses them; client variant doesn't do OTA.
$Arm64Release = Join-Path $BuildsDir "terraton-fan-arm64.apk"
$Arm7Release  = Join-Path $BuildsDir "terraton-fan-arm7.apk"
$X86Release   = Join-Path $BuildsDir "terraton-fan-x86_64.apk"

if ($buildTester) {
    Write-Host ""
    Write-Host "Building TESTER variant (all features + OTA)..." -ForegroundColor Cyan
    flutter build apk --release --split-per-abi `
        --dart-define="UPLOAD_API_KEY=$UploadApiKey" `
        --dart-define="APP_VARIANT=tester"
    if ($LASTEXITCODE -ne 0) { Write-Host "Tester build failed." -ForegroundColor Red; exit 1 }

    $Arm64 = Join-Path $ApkDir "app-arm64-v8a-release.apk"
    $Arm7  = Join-Path $ApkDir "app-armeabi-v7a-release.apk"
    $X86   = Join-Path $ApkDir "app-x86_64-release.apk"
    if (-not (Test-Path $Arm64)) { Write-Host "arm64 APK not found at: $Arm64" -ForegroundColor Red; exit 1 }

    Copy-Item $Arm64 (Join-Path $BuildsDir "terraton-tester-arm64-$Timestamp.apk")
    Write-Host "Saved tester arm64" -ForegroundColor Green
    if (Test-Path $Arm7) { Copy-Item $Arm7 (Join-Path $BuildsDir "terraton-tester-arm7-$Timestamp.apk");  Write-Host "Saved tester arm7"   -ForegroundColor Green }
    if (Test-Path $X86)  { Copy-Item $X86  (Join-Path $BuildsDir "terraton-tester-x86_64-$Timestamp.apk"); Write-Host "Saved tester x86_64" -ForegroundColor Green }

    # Fixed-name copies for OTA download URLs (app_update_service.dart expects these).
    Copy-Item $Arm64 $Arm64Release
    if (Test-Path $Arm7) { Copy-Item $Arm7 $Arm7Release }
    if (Test-Path $X86)  { Copy-Item $X86  $X86Release  }
}

if ($buildClient) {
    Write-Host ""
    Write-Host "Building CLIENT variant (fans only, no OTA)..." -ForegroundColor Cyan
    flutter build apk --release --split-per-abi `
        --dart-define="UPLOAD_API_KEY=$UploadApiKey" `
        --dart-define="APP_VARIANT=client"
    if ($LASTEXITCODE -ne 0) { Write-Host "Client build failed." -ForegroundColor Red; exit 1 }

    $Arm64 = Join-Path $ApkDir "app-arm64-v8a-release.apk"
    $Arm7  = Join-Path $ApkDir "app-armeabi-v7a-release.apk"
    $X86   = Join-Path $ApkDir "app-x86_64-release.apk"
    if (-not (Test-Path $Arm64)) { Write-Host "arm64 APK not found at: $Arm64" -ForegroundColor Red; exit 1 }

    Copy-Item $Arm64 (Join-Path $BuildsDir "terraton-client-arm64-$Timestamp.apk")
    Write-Host "Saved client arm64" -ForegroundColor Green
    if (Test-Path $Arm7) { Copy-Item $Arm7 (Join-Path $BuildsDir "terraton-client-arm7-$Timestamp.apk");  Write-Host "Saved client arm7"   -ForegroundColor Green }
    if (Test-Path $X86)  { Copy-Item $X86  (Join-Path $BuildsDir "terraton-client-x86_64-$Timestamp.apk"); Write-Host "Saved client x86_64" -ForegroundColor Green }
}

if (-not $buildTester -and -not $buildClient) {
    Write-Host "No variant selected — nothing to build." -ForegroundColor Yellow
    exit 0
}

# ── 6. Publish tester variant to GitHub Releases (OTA update source) ──────────
# Client variant is distributed directly (share the APK); it has no OTA check.
if ($buildTester) {
    # Write version.json for OTA version check.
    # IMPORTANT: use WriteAllText with UTF8Encoding(false) — Set-Content -Encoding utf8 in
    # PowerShell 5.1 adds a BOM which breaks jsonDecode() in the app.
    $VersionJsonPath = Join-Path $BuildsDir "version.json"
    $versionJsonContent = "{`"version`": `"$SemVer`", `"build_number`": $BuildNum}"
    [System.IO.File]::WriteAllText($VersionJsonPath, $versionJsonContent, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "version.json : v$SemVer (build $BuildNum)" -ForegroundColor Green

    Write-Host ""
    Write-Host "Publishing TESTER variant to GitHub Releases..." -ForegroundColor Cyan
    Set-Location $ProjectRoot

    # Delete existing 'latest' release and tag so we can replace it cleanly
    gh release delete $ReleaseTag --repo $Repo --yes 2>$null
    git tag -d $ReleaseTag 2>$null
    git push origin --delete $ReleaseTag 2>$null

    # Collect release assets: fixed-name APKs + version.json (OTA update relies on these)
    $Assets = @($Arm64Release, $VersionJsonPath)
    if (Test-Path $Arm7Release) { $Assets += $Arm7Release }
    if (Test-Path $X86Release)  { $Assets += $X86Release  }

    $BuildDate = Get-Date -Format "yyyy-MM-dd HH:mm"
    $Notes = @"
**v$NewVersion** - built $BuildDate  |  **Tester variant** (all features + OTA updates)

Both QR scan and Bluetooth scan onboarding are included in every APK.

| APK | Architecture | Use for |
|-----|-------------|---------|
| terraton-fan-arm64.apk | arm64-v8a | All modern Android phones (recommended) |
| terraton-fan-arm7.apk  | armeabi-v7a | Older 32-bit Android phones |
| terraton-fan-x86_64.apk | x86_64 | Android emulators |

> **Client variant** (fans only, no OTA) is built locally as `terraton-client-arm64-*.apk` in the `builds/` folder. Share it directly with end users.
"@

    gh release create $ReleaseTag @Assets `
        --repo $Repo `
        --title "v$NewVersion ($BuildDate) [tester]" `
        --notes $Notes `
        --latest

    if ($LASTEXITCODE -ne 0) {
        Write-Host "GitHub release upload failed." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "Skipping GitHub release (tester variant not built)." -ForegroundColor DarkGray
    Write-Host "Client APKs are in builds/ - share terraton-client-arm64-*.apk directly." -ForegroundColor Cyan
}

# ── 7. Commit & push the version bump ────────────────────────────────────────
if ($bumpChoice.Trim().ToUpper() -ne 'S') {
    Set-Location $ProjectRoot
    # Only commit if pubspec.yaml actually has uncommitted changes.
    $dirty = git status --porcelain $PubspecPath 2>&1
    if ($dirty) {
        git add $PubspecPath (Join-Path $AppDir "pubspec.lock")
        git commit -m "chore: bump version to $NewVersion"
        if ($LASTEXITCODE -eq 0) {
            git push
            Write-Host "Committed and pushed version bump  ->  $NewVersion" -ForegroundColor Green
        } else {
            Write-Host "Warning: git commit failed - commit pubspec.yaml manually." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Version $NewVersion already committed." -ForegroundColor DarkGray
    }
}

# Restart OneDrive sync
$odExe = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
if (Test-Path $odExe) {
    Start-Process $odExe
    Write-Host "OneDrive sync resumed." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Done!  v$NewVersion" -ForegroundColor Green
if ($buildTester) {
    Write-Host "Tester APK (OTA-enabled):   https://github.com/$Repo/releases/latest/download/terraton-fan-arm64.apk" -ForegroundColor Cyan
}
if ($buildClient) {
    $clientApk = Get-ChildItem (Join-Path $BuildsDir "terraton-client-arm64-*.apk") | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($clientApk) {
        Write-Host "Client APK (share directly): $($clientApk.FullName)" -ForegroundColor Cyan
    }
}
