#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Local MLOps retraining script — run this on your laptop instead of GitHub Actions.

.DESCRIPTION
    1. Reads R2 credentials from ml/.r2.env (gitignored)
    2. Checks R2 data health — aborts if fewer than 500 rows
    3. Runs Phase 1 (XGBoost) always
    4. Runs Phase 2 (Keras -> TFLite) when 10,000+ rows
    5. Uploads new model + updates models/latest.json in R2

.EXAMPLE
    # Full run (Phase 1 + 2 when enough data):
    .\ml\retrain.ps1

    # Phase 1 only (XGBoost, no TFLite):
    .\ml\retrain.ps1 -Phase 1

    # Override row requirement for testing:
    .\ml\retrain.ps1 -MinRowsOverride 0

.NOTES
    Prerequisites:
      - Python 3.11+ on PATH
      - ml\.r2.env with R2_ENDPOINT, R2_ACCESS_KEY, R2_SECRET_KEY (see below)

    Create ml\.r2.env (already in .gitignore) with:
      R2_ENDPOINT=https://<your-account-id>.r2.cloudflarestorage.com
      R2_ACCESS_KEY=<r2-access-key-id>
      R2_SECRET_KEY=<r2-secret-access-key>
#>

param(
    [ValidateSet('1', '2')]
    [string]$Phase = '2',
    [int]$MinRowsOverride = 0
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot\..

# ── Load R2 credentials ──────────────────────────────────────────────────────
$envFile = "ml\.r2.env"
if (-not (Test-Path $envFile)) {
    Write-Error @"
Missing $envFile

Create it with:
  R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
  R2_ACCESS_KEY=<r2-access-key-id>
  R2_SECRET_KEY=<r2-secret-access-key>

Get these from: Cloudflare Dashboard -> R2 -> Manage R2 API Tokens
"@
    exit 1
}

foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
    $parts = $line -split '=', 2
    [System.Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), 'Process')
}

# ── Python virtual environment ───────────────────────────────────────────────
$venv = "ml\.venv"
if (-not (Test-Path "$venv\Scripts\python.exe")) {
    Write-Host "Creating Python virtual environment..." -ForegroundColor Cyan
    python -m venv $venv
}

$pip  = "$venv\Scripts\pip.exe"
$py   = "$venv\Scripts\python.exe"

Write-Host "Installing/updating ML dependencies..." -ForegroundColor Cyan
& $pip install -q -r ml\requirements.txt

# ── Data health check ────────────────────────────────────────────────────────
Write-Host "`n[1/4] Checking R2 data..." -ForegroundColor Yellow
$healthJson = & $py ml\data_health.py --json --no-exit | ConvertFrom-Json

$rows = [int]$healthJson.total_rows
Write-Host "      Total rows : $rows"
Write-Host "      Last upload: $($healthJson.last_upload_age_hours)h ago"
Write-Host "      Status     : $($healthJson.message)"

$minPhase1 = if ($MinRowsOverride -gt 0) { $MinRowsOverride } else { 500 }
$minPhase2 = if ($MinRowsOverride -gt 0) { $MinRowsOverride } else { 10000 }

if ($rows -lt $minPhase1) {
    Write-Host "`nOnly $rows rows -- need $minPhase1 for Phase 1. Aborting." -ForegroundColor Red
    exit 0
}

# ── Phase 1: XGBoost ────────────────────────────────────────────────────────
Write-Host "`n[2/4] Phase 1 -- XGBoost baseline..." -ForegroundColor Yellow
& $py ml\train.py --phase 1
if ($LASTEXITCODE -ne 0) { Write-Error "Phase 1 training failed."; exit 1 }
Write-Host "      Phase 1 complete. Artifacts: ml\output\gear_xgb.json, savings_xgb.json, shap_importance.png"

if ($Phase -eq '1') {
    Write-Host "`nPhase 1 only requested. Done." -ForegroundColor Green
    exit 0
}

# ── Phase 2: Keras -> TFLite ─────────────────────────────────────────────────
if ($rows -ge $minPhase2) {
    Write-Host "`n[3/4] Phase 2 -- Two-tower Keras + TFLite..." -ForegroundColor Yellow
    & $py ml\train.py --phase 2
    if ($LASTEXITCODE -ne 0) { Write-Error "Phase 2 training failed."; exit 1 }
    Write-Host "      Phase 2 complete. Model: ml\output\terraton_recommender_fp16.tflite"

    # ── Upload to R2 ─────────────────────────────────────────────────────────
    Write-Host "`n[4/4] Uploading model to R2..." -ForegroundColor Yellow
    & $py ml\upload_model.py
    if ($LASTEXITCODE -ne 0) { Write-Error "Model upload failed."; exit 1 }
} else {
    Write-Host "`n[3/4] Phase 2 skipped -- need $minPhase2 rows (have $rows)." -ForegroundColor DarkYellow
    Write-Host "[4/4] Upload skipped (no new model)." -ForegroundColor DarkYellow
}

Write-Host "`nRetraining complete." -ForegroundColor Green
