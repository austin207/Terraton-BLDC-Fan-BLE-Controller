# build.ps1 — Build Terraton Fan APK and copy to builds/

$ProjectRoot = $PSScriptRoot
$AppDir      = Join-Path $ProjectRoot "terraton_fan_app"
$BuildsDir   = Join-Path $ProjectRoot "builds"

Write-Host "Building Terraton Fan APK..." -ForegroundColor Cyan

Set-Location $AppDir

flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit 1
}

$Apk = Join-Path $AppDir "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $Apk)) {
    Write-Host "APK not found at expected path: $Apk" -ForegroundColor Red
    exit 1
}

$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputName = "terraton-fan-$Timestamp.apk"
$OutputPath = Join-Path $BuildsDir $OutputName

Copy-Item $Apk $OutputPath

Write-Host ""
Write-Host "Done! APK saved to:" -ForegroundColor Green
Write-Host "  $OutputPath" -ForegroundColor White
