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
$PubspecRaw  = Get-Content $PubspecPath -Raw
if ($PubspecRaw -match 'version:\s+(\d+)\.(\d+)\.(\d+)\+(\d+)') {
    $vMaj = [int]$Matches[1]; $vMin = [int]$Matches[2]
    $vPat = [int]$Matches[3]; $vBld = [int]$Matches[4]
} else {
    Write-Host "ERROR: Could not parse version from pubspec.yaml (expected format: x.y.z+N)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Current version: $vMaj.$vMin.$vPat+$vBld" -ForegroundColor Yellow
Write-Host "  [P]atch  ->  $vMaj.$vMin.$($vPat + 1)+$($vBld + 1)   (default — small fixes / tweaks)"     -ForegroundColor DarkGray
Write-Host "  mi[N]or  ->  $vMaj.$($vMin + 1).0+$($vBld + 1)   (new features, backwards-compatible)"      -ForegroundColor DarkGray
Write-Host "  ma[J]or  ->  $($vMaj + 1).0.0+$($vBld + 1)   (breaking changes / landmark release)"         -ForegroundColor DarkGray
Write-Host "  [S]kip   ->  keep $vMaj.$vMin.$vPat+$vBld  (rebuild without bumping)"                        -ForegroundColor DarkGray
Write-Host ""
$bumpChoice = Read-Host "Bump type [P/N/J/S]"
if ([string]::IsNullOrEmpty($bumpChoice)) { $bumpChoice = 'P' }

switch ($bumpChoice.Trim().ToUpper()) {
    'P' { $vPat++;                          $vBld++ }
    'N' { $vMin++; $vPat = 0;              $vBld++ }
    'J' { $vMaj++; $vMin = 0; $vPat = 0;  $vBld++ }
    'S' { <# no change #> }
    default { Write-Host "Unknown input — defaulting to Patch." -ForegroundColor Yellow; $vPat++; $vBld++ }
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

flutter build apk --release --split-per-abi `
    --dart-define="UPLOAD_API_KEY=$UploadApiKey"
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

# ── 4. Save timestamped copies locally + write release assets ────────────────
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

# Fixed-name copies for stable OTA download URLs (app_update_service.dart expects these names)
$Arm64Release = Join-Path $BuildsDir "terraton-fan-arm64.apk"
$Arm7Release  = Join-Path $BuildsDir "terraton-fan-arm7.apk"
$X86Release   = Join-Path $BuildsDir "terraton-fan-x86_64.apk"
Copy-Item $Arm64 $Arm64Release
if (Test-Path $Arm7)  { Copy-Item $Arm7 $Arm7Release  }
if (Test-Path $X86)   { Copy-Item $X86  $X86Release   }

# Write version.json for OTA version check (version already set by bump prompt)
$VersionJsonPath = Join-Path $BuildsDir "version.json"
Set-Content -Path $VersionJsonPath -Value "{`"version`": `"$SemVer`", `"build_number`": $BuildNum}" -Encoding utf8
Write-Host "version.json : v$SemVer (build $BuildNum)" -ForegroundColor Green

# ── 5. Publish to GitHub Releases (tag: latest) ───────────────────────────────
Write-Host ""
Write-Host "Publishing to GitHub Releases..." -ForegroundColor Cyan
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
**v$NewVersion** — built $BuildDate

Both QR scan and Bluetooth scan onboarding are included in every APK.

| APK | Architecture | Use for |
|-----|-------------|---------|
| terraton-fan-arm64.apk | arm64-v8a | All modern Android phones (recommended) |
| terraton-fan-arm7.apk  | armeabi-v7a | Older 32-bit Android phones |
| terraton-fan-x86_64.apk | x86_64 | Android emulators |
"@

gh release create $ReleaseTag @Assets `
    --repo $Repo `
    --title "v$NewVersion ($BuildDate)" `
    --notes $Notes `
    --latest

if ($LASTEXITCODE -ne 0) {
    Write-Host "GitHub release upload failed." -ForegroundColor Red
    exit 1
}

# ── 6. Commit & push the version bump ────────────────────────────────────────
if ($bumpChoice.Trim().ToUpper() -ne 'S') {
    Set-Location $ProjectRoot
    git add (Join-Path $AppDir "pubspec.yaml") (Join-Path $AppDir "pubspec.lock")
    git commit -m "chore: bump version to $NewVersion"
    if ($LASTEXITCODE -eq 0) {
        git push
        Write-Host "Committed and pushed version bump  ->  $NewVersion" -ForegroundColor Green
    } else {
        Write-Host "Warning: git commit failed — commit pubspec.yaml manually." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done!  v$NewVersion" -ForegroundColor Green
Write-Host "Recommended download (arm64): https://github.com/$Repo/releases/latest/download/terraton-fan-arm64.apk" -ForegroundColor Cyan
