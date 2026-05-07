# build.ps1 — Build Terraton Fan APK, save locally, and publish to GitHub Releases

$ProjectRoot = $PSScriptRoot
$AppDir      = Join-Path $ProjectRoot "terraton_fan_app"
$BuildsDir   = Join-Path $ProjectRoot "builds"
$Repo        = "austin207/Terraton-BLDC-Fan-BLE-Controller"
$ReleaseTag  = "latest"

# ── 1. Build ─────────────────────────────────────────────────────────────────
Write-Host "Building Terraton Fan APK..." -ForegroundColor Cyan
Set-Location $AppDir

flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit 1
}

$Apk = Join-Path $AppDir "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $Apk)) {
    Write-Host "APK not found at: $Apk" -ForegroundColor Red
    exit 1
}

# ── 2. Save timestamped copy locally ─────────────────────────────────────────
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$LocalName  = "terraton-fan-$Timestamp.apk"
$LocalPath  = Join-Path $BuildsDir $LocalName
Copy-Item $Apk $LocalPath
Write-Host "Saved locally: $LocalPath" -ForegroundColor Green

# ── 3. Publish to GitHub Releases (tag: latest) ───────────────────────────────
Write-Host ""
Write-Host "Publishing to GitHub Releases..." -ForegroundColor Cyan
Set-Location $ProjectRoot

# Delete existing 'latest' release and tag so we can replace it cleanly
gh release delete $ReleaseTag --repo $Repo --yes 2>$null
git tag -d $ReleaseTag 2>$null
git push origin --delete $ReleaseTag 2>$null

# Create fresh release with the APK attached
$BuildDate = Get-Date -Format "yyyy-MM-dd HH:mm"
gh release create $ReleaseTag $LocalPath `
    --repo $Repo `
    --title "Latest Build ($BuildDate)" `
    --notes "Automated release. Built on $BuildDate." `
    --latest

if ($LASTEXITCODE -ne 0) {
    Write-Host "GitHub release upload failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host "Direct download: https://github.com/$Repo/releases/latest/download/$LocalName" -ForegroundColor Cyan
