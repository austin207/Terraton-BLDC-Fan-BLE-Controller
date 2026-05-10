# Generates terraton_fan_app/assets/icon/icon.png
# 3-blade ceiling fan propeller on a blue rounded square (1024x1024).
# Run from repo root: .\scripts\generate_icon.ps1
# Then regenerate launcher icons: cd terraton_fan_app && dart run flutter_launcher_icons

Add-Type -AssemblyName System.Drawing

$size = 1024
$bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

# ── Blue rounded rectangle background ──────────────────────────────
$cr = 236; $d = $cr * 2
$bgB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 26, 86, 160))
$bgP = New-Object System.Drawing.Drawing2D.GraphicsPath
$bgP.AddArc(0,         0,         $d, $d, 180, 90)
$bgP.AddArc($size - $d, 0,        $d, $d, 270, 90)
$bgP.AddArc($size - $d, $size-$d, $d, $d,   0, 90)
$bgP.AddArc(0,          $size-$d, $d, $d,  90, 90)
$bgP.CloseFigure()
$g.FillPath($bgB, $bgP)

# ── 3-blade propeller ───────────────────────────────────────────────
# Bezier skeleton — blade points upward (-Y); rotated 0°/120°/240°.
# 10 points: P0 = start, then 3 × (cp1, cp2, end).
$cx = 512.0; $cy = 512.0; $R = [double]($size * 0.36)

$lxF = @( 0.10,  0.32,  0.50,  0.36,  0.24, -0.04, -0.18, -0.30, -0.18, -0.10)
$lyF = @(-0.12, -0.22, -0.58, -0.88, -0.99, -0.99, -0.88, -0.65, -0.35, -0.12)

$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

for ($blade = 0; $blade -lt 3; $blade++) {
    $angle = [double]$blade * 2.0 * [Math]::PI / 3.0
    $cos   = [Math]::Cos($angle)
    $sin   = [Math]::Sin($angle)

    $pts = New-Object 'System.Drawing.PointF[]' 10
    for ($j = 0; $j -lt 10; $j++) {
        $lx     = [double]$lxF[$j] * $R
        $ly     = [double]$lyF[$j] * $R
        $pts[$j] = [System.Drawing.PointF]::new(
            [float]($lx * $cos - $ly * $sin + $cx),
            [float]($lx * $sin + $ly * $cos + $cy)
        )
    }

    $bp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $bp.AddBeziers($pts)
    $bp.CloseFigure()
    $g.FillPath($white, $bp)
}

# ── Centre hub ───────────────────────────────────────────────────────
$hubR = [float]($R * 0.11)
$hubD = [float]($hubR * 2)
$g.FillEllipse($white, [float]($cx - $hubR), [float]($cy - $hubR), $hubD, $hubD)

# ── Save ─────────────────────────────────────────────────────────────
$out = Join-Path $PSScriptRoot "..\terraton_fan_app\assets\icon\icon.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "Saved $((Get-Item $out).Length) bytes to $out"
