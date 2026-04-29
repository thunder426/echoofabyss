Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

$canvasSize = 512
$center = [System.Drawing.PointF]::new($canvasSize / 2.0, $canvasSize / 2.0)
$transparent = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)
$lineColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

$outputDir = Join-Path $PSScriptRoot "..\echoofabyss\assets\art\fx\casting_glyphs\summon_sigil"
$broodOutputDir = Join-Path $PSScriptRoot "..\echoofabyss\assets\art\fx\casting_glyphs\brood_sigil"
$sparkOutputDir = Join-Path $PSScriptRoot "..\echoofabyss\assets\art\fx\casting_glyphs\spark_sigil"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
New-Item -ItemType Directory -Force -Path $broodOutputDir | Out-Null
New-Item -ItemType Directory -Force -Path $sparkOutputDir | Out-Null

function New-GlyphBitmap {
	param([int]$Size)

	$bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
	$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
	$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
	$graphics.Clear($transparent)

	return @{
		Bitmap = $bitmap
		Graphics = $graphics
	}
}

function New-RoundPen {
	param(
		[int]$Width
	)

	$pen = [System.Drawing.Pen]::new($lineColor, $Width)
	$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
	$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
	$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
	return $pen
}

function Draw-Circle {
	param(
		[System.Drawing.Graphics]$Graphics,
		[System.Drawing.Pen]$Pen,
		[float]$Radius
	)

	$diameter = $Radius * 2.0
	$Graphics.DrawEllipse($Pen, $center.X - $Radius, $center.Y - $Radius, $diameter, $diameter)
}

function Draw-ArcRing {
	param(
		[System.Drawing.Graphics]$Graphics,
		[System.Drawing.Pen]$Pen,
		[float]$Radius,
		[int]$ArcCount,
		[float]$ArcSweep,
		[float]$StartOffsetDegrees
	)

	$diameter = $Radius * 2.0
	$step = 360.0 / $ArcCount
	for ($i = 0; $i -lt $ArcCount; $i++) {
		$startAngle = $StartOffsetDegrees + ($i * $step)
		$Graphics.DrawArc($Pen, $center.X - $Radius, $center.Y - $Radius, $diameter, $diameter, $startAngle, $ArcSweep)
	}
}

function Draw-Diamond {
	param(
		[System.Drawing.Graphics]$Graphics,
		[System.Drawing.Pen]$Pen,
		[float]$Distance,
		[float]$HalfWidth,
		[float]$HalfHeight,
		[float]$AngleDegrees
	)

	$theta = [Math]::PI * $AngleDegrees / 180.0
	$x = $center.X + ([Math]::Cos($theta) * $Distance)
	$y = $center.Y + ([Math]::Sin($theta) * $Distance)

	$points = [System.Drawing.PointF[]]@(
		[System.Drawing.PointF]::new($x, $y - $HalfHeight),
		[System.Drawing.PointF]::new($x + $HalfWidth, $y),
		[System.Drawing.PointF]::new($x, $y + $HalfHeight),
		[System.Drawing.PointF]::new($x - $HalfWidth, $y)
	)
	$Graphics.DrawPolygon($Pen, $points)
}

function Draw-Triangle {
	param(
		[System.Drawing.Graphics]$Graphics,
		[System.Drawing.Pen]$Pen,
		[float]$TopY,
		[float]$HalfWidth,
		[float]$BottomY
	)

	$points = [System.Drawing.PointF[]]@(
		[System.Drawing.PointF]::new($center.X, $TopY),
		[System.Drawing.PointF]::new($center.X + $HalfWidth, $BottomY),
		[System.Drawing.PointF]::new($center.X - $HalfWidth, $BottomY)
	)
	$Graphics.DrawPolygon($Pen, $points)
}

function New-PolarPoint {
	param(
		[float]$Radius,
		[float]$AngleDegrees
	)

	$theta = [Math]::PI * $AngleDegrees / 180.0
	return [System.Drawing.PointF]::new(
		$center.X + ([Math]::Cos($theta) * $Radius),
		$center.Y + ([Math]::Sin($theta) * $Radius)
	)
}

function Draw-HookArc {
	param(
		[System.Drawing.Graphics]$Graphics,
		[System.Drawing.Pen]$Pen,
		[float]$Radius,
		[float]$AngleDegrees,
		[float]$SweepDirection
	)

	$start = New-PolarPoint -Radius $Radius -AngleDegrees ($AngleDegrees - 16)
	$tip = New-PolarPoint -Radius ($Radius + 26) -AngleDegrees ($AngleDegrees + (8 * $SweepDirection))
	$end = New-PolarPoint -Radius $Radius -AngleDegrees ($AngleDegrees + 18)
	$ctrl1 = New-PolarPoint -Radius ($Radius + 10) -AngleDegrees ($AngleDegrees - 5)
	$ctrl2 = New-PolarPoint -Radius ($Radius + 22) -AngleDegrees ($AngleDegrees + (18 * $SweepDirection))
	$ctrl3 = New-PolarPoint -Radius ($Radius + 18) -AngleDegrees ($AngleDegrees + (4 * $SweepDirection))
	$ctrl4 = New-PolarPoint -Radius ($Radius + 8) -AngleDegrees ($AngleDegrees + 8)

	$Graphics.DrawBezier($Pen, $start, $ctrl1, $ctrl2, $tip)
	$Graphics.DrawBezier($Pen, $tip, $ctrl3, $ctrl4, $end)
}

function Draw-SeedGlyph {
	param(
		[System.Drawing.Graphics]$Graphics,
		[System.Drawing.Pen]$Pen,
		[float]$RadiusX,
		[float]$RadiusY
	)

	$Graphics.DrawEllipse($Pen, $center.X - $RadiusX, $center.Y - $RadiusY, $RadiusX * 2.0, $RadiusY * 2.0)
}

function Draw-ClawSprout {
	param(
		[System.Drawing.Graphics]$Graphics,
		[System.Drawing.Pen]$Pen,
		[float]$AngleDegrees,
		[float]$RootRadius,
		[float]$TipRadius,
		[float]$CurlDegrees,
		[float]$WidthDegrees
	)

	$start = New-PolarPoint -Radius $RootRadius -AngleDegrees ($AngleDegrees - ($WidthDegrees * 0.55))
	$root = New-PolarPoint -Radius ($RootRadius - 6) -AngleDegrees $AngleDegrees
	$tip = New-PolarPoint -Radius $TipRadius -AngleDegrees ($AngleDegrees + $CurlDegrees)
	$end = New-PolarPoint -Radius $RootRadius -AngleDegrees ($AngleDegrees + ($WidthDegrees * 0.45))
	$ctrl1 = New-PolarPoint -Radius ($RootRadius + (($TipRadius - $RootRadius) * 0.28)) -AngleDegrees ($AngleDegrees - ($WidthDegrees * 0.15))
	$ctrl2 = New-PolarPoint -Radius ($RootRadius + (($TipRadius - $RootRadius) * 0.72)) -AngleDegrees ($AngleDegrees + ($CurlDegrees * 0.65))
	$ctrl3 = New-PolarPoint -Radius ($RootRadius + (($TipRadius - $RootRadius) * 0.58)) -AngleDegrees ($AngleDegrees + ($CurlDegrees * 1.08))
	$ctrl4 = New-PolarPoint -Radius ($RootRadius + (($TipRadius - $RootRadius) * 0.16)) -AngleDegrees ($AngleDegrees + ($WidthDegrees * 0.28))

	$Graphics.DrawBezier($Pen, $start, $ctrl1, $ctrl2, $tip)
	$Graphics.DrawBezier($Pen, $tip, $ctrl3, $ctrl4, $end)
	$Graphics.DrawLine($Pen, $start, $root)
	$Graphics.DrawLine($Pen, $root, $end)
}

function Draw-Tick {
	param(
		[System.Drawing.Graphics]$Graphics,
		[System.Drawing.Pen]$Pen,
		[float]$InnerRadius,
		[float]$OuterRadius,
		[float]$AngleDegrees
	)

	$start = New-PolarPoint -Radius $InnerRadius -AngleDegrees $AngleDegrees
	$end = New-PolarPoint -Radius $OuterRadius -AngleDegrees $AngleDegrees
	$Graphics.DrawLine($Pen, $start, $end)
}

function Save-Bitmap {
	param(
		[System.Drawing.Bitmap]$Bitmap,
		[string]$Path
	)

	$Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function Build-OuterRing {
	$asset = New-GlyphBitmap -Size $canvasSize
	$graphics = $asset.Graphics
	$bitmap = $asset.Bitmap

	$heavyPen = New-RoundPen -Width 12
	$accentPen = New-RoundPen -Width 10

	Draw-Circle -Graphics $graphics -Pen $heavyPen -Radius 210
	Draw-ArcRing -Graphics $graphics -Pen $accentPen -Radius 184 -ArcCount 4 -ArcSweep 34 -StartOffsetDegrees -17

	foreach ($angle in @( -90, 0, 90, 180 )) {
		Draw-Diamond -Graphics $graphics -Pen $accentPen -Distance 236 -HalfWidth 14 -HalfHeight 9 -AngleDegrees $angle
	}

	$heavyPen.Dispose()
	$accentPen.Dispose()

	$path = Join-Path $outputDir "summon_outer_ring.png"
	Save-Bitmap -Bitmap $bitmap -Path $path

	$graphics.Dispose()
	$bitmap.Dispose()
}

function Build-InnerRing {
	$asset = New-GlyphBitmap -Size $canvasSize
	$graphics = $asset.Graphics
	$bitmap = $asset.Bitmap

	$heavyPen = New-RoundPen -Width 12
	$accentPen = New-RoundPen -Width 10

	Draw-Circle -Graphics $graphics -Pen $heavyPen -Radius 150
	Draw-ArcRing -Graphics $graphics -Pen $accentPen -Radius 124 -ArcCount 8 -ArcSweep 18 -StartOffsetDegrees -9

	foreach ($angle in @(45, 135, 225, 315)) {
		Draw-Diamond -Graphics $graphics -Pen $accentPen -Distance 170 -HalfWidth 10 -HalfHeight 7 -AngleDegrees $angle
	}

	$heavyPen.Dispose()
	$accentPen.Dispose()

	$path = Join-Path $outputDir "summon_inner_ring.png"
	Save-Bitmap -Bitmap $bitmap -Path $path

	$graphics.Dispose()
	$bitmap.Dispose()
}

function Build-CenterGlyph {
	$asset = New-GlyphBitmap -Size $canvasSize
	$graphics = $asset.Graphics
	$bitmap = $asset.Bitmap

	$mainPen = New-RoundPen -Width 11
	$detailPen = New-RoundPen -Width 9

	Draw-Triangle -Graphics $graphics -Pen $mainPen -TopY 165 -HalfWidth 76 -BottomY 320

	$graphics.DrawArc($detailPen, 190, 220, 132, 58, 200, 140)
	$graphics.DrawLine($detailPen, 256, 214, 256, 286)
	$graphics.DrawLine($detailPen, 232, 250, 280, 250)

	Draw-Diamond -Graphics $graphics -Pen $detailPen -Distance 0 -HalfWidth 14 -HalfHeight 20 -AngleDegrees 0
	Draw-Diamond -Graphics $graphics -Pen $detailPen -Distance 82 -HalfWidth 10 -HalfHeight 16 -AngleDegrees -90
	Draw-Diamond -Graphics $graphics -Pen $detailPen -Distance 82 -HalfWidth 10 -HalfHeight 16 -AngleDegrees 90

	$mainPen.Dispose()
	$detailPen.Dispose()

	$path = Join-Path $outputDir "summon_center_glyph.png"
	Save-Bitmap -Bitmap $bitmap -Path $path

	$graphics.Dispose()
	$bitmap.Dispose()
}

Build-OuterRing
Build-InnerRing
Build-CenterGlyph

function Build-BroodOuterRing {
	$asset = New-GlyphBitmap -Size $canvasSize
	$graphics = $asset.Graphics
	$bitmap = $asset.Bitmap

	$mainPen = New-RoundPen -Width 11
	$detailPen = New-RoundPen -Width 8

	Draw-Circle -Graphics $graphics -Pen $mainPen -Radius 205
	Draw-Circle -Graphics $graphics -Pen $detailPen -Radius 188

	foreach ($angle in @( -90, -30, 30, 90, 150, 210 )) {
		Draw-HookArc -Graphics $graphics -Pen $mainPen -Radius 201 -AngleDegrees $angle -SweepDirection 1
	}

	foreach ($angle in @( -90, 0, 90, 180 )) {
		Draw-Diamond -Graphics $graphics -Pen $detailPen -Distance 232 -HalfWidth 12 -HalfHeight 8 -AngleDegrees $angle
	}

	foreach ($angle in @( -45, 45, 135, 225 )) {
		$graphics.DrawArc($detailPen, 256 - 218, 256 - 218, 436, 436, $angle - 9, 18)
	}

	$mainPen.Dispose()
	$detailPen.Dispose()

	$path = Join-Path $broodOutputDir "brood_outer_ring.png"
	Save-Bitmap -Bitmap $bitmap -Path $path

	$graphics.Dispose()
	$bitmap.Dispose()
}

function Build-BroodInnerRing {
	$asset = New-GlyphBitmap -Size $canvasSize
	$graphics = $asset.Graphics
	$bitmap = $asset.Bitmap

	$mainPen = New-RoundPen -Width 10
	$detailPen = New-RoundPen -Width 8

	Draw-Circle -Graphics $graphics -Pen $mainPen -Radius 145

	foreach ($angle in @( -90, -30, 30, 90, 150, 210 )) {
		Draw-HookArc -Graphics $graphics -Pen $mainPen -Radius 132 -AngleDegrees $angle -SweepDirection -1
	}

	foreach ($angle in @( -90, 30, 150 )) {
		$start = New-PolarPoint -Radius 84 -AngleDegrees ($angle - 10)
		$tip = New-PolarPoint -Radius 124 -AngleDegrees $angle
		$end = New-PolarPoint -Radius 84 -AngleDegrees ($angle + 10)
		$ctrl1 = New-PolarPoint -Radius 98 -AngleDegrees ($angle - 6)
		$ctrl2 = New-PolarPoint -Radius 118 -AngleDegrees ($angle - 2)
		$ctrl3 = New-PolarPoint -Radius 118 -AngleDegrees ($angle + 2)
		$ctrl4 = New-PolarPoint -Radius 98 -AngleDegrees ($angle + 6)
		$graphics.DrawBezier($detailPen, $start, $ctrl1, $ctrl2, $tip)
		$graphics.DrawBezier($detailPen, $tip, $ctrl3, $ctrl4, $end)
	}

	foreach ($angle in @( -30, 90, 210 )) {
		Draw-Diamond -Graphics $graphics -Pen $detailPen -Distance 162 -HalfWidth 9 -HalfHeight 6 -AngleDegrees $angle
	}

	$mainPen.Dispose()
	$detailPen.Dispose()

	$path = Join-Path $broodOutputDir "brood_inner_ring.png"
	Save-Bitmap -Bitmap $bitmap -Path $path

	$graphics.Dispose()
	$bitmap.Dispose()
}

function Build-BroodCenterGlyph {
	$asset = New-GlyphBitmap -Size $canvasSize
	$graphics = $asset.Graphics
	$bitmap = $asset.Bitmap

	$mainPen = New-RoundPen -Width 10
	$detailPen = New-RoundPen -Width 8

	Draw-SeedGlyph -Graphics $graphics -Pen $mainPen -RadiusX 32 -RadiusY 52
	$graphics.DrawLine($detailPen, 256, 205, 256, 307)
	$graphics.DrawArc($detailPen, 224, 216, 64, 42, 200, 140)
	$graphics.DrawArc($detailPen, 224, 254, 64, 42, 20, 140)

	foreach ($angle in @( -110, 0, 110 )) {
		$base = New-PolarPoint -Radius 52 -AngleDegrees $angle
		$tip = New-PolarPoint -Radius 112 -AngleDegrees ($angle + 8)
		$return = New-PolarPoint -Radius 58 -AngleDegrees ($angle + 18)
		$ctrl1 = New-PolarPoint -Radius 74 -AngleDegrees ($angle - 4)
		$ctrl2 = New-PolarPoint -Radius 104 -AngleDegrees ($angle + 2)
		$ctrl3 = New-PolarPoint -Radius 90 -AngleDegrees ($angle + 20)
		$ctrl4 = New-PolarPoint -Radius 70 -AngleDegrees ($angle + 18)
		$graphics.DrawBezier($mainPen, $base, $ctrl1, $ctrl2, $tip)
		$graphics.DrawBezier($mainPen, $tip, $ctrl3, $ctrl4, $return)
	}

	Draw-Diamond -Graphics $graphics -Pen $detailPen -Distance 0 -HalfWidth 12 -HalfHeight 18 -AngleDegrees 0
	Draw-Diamond -Graphics $graphics -Pen $detailPen -Distance 74 -HalfWidth 8 -HalfHeight 12 -AngleDegrees -90
	Draw-Diamond -Graphics $graphics -Pen $detailPen -Distance 74 -HalfWidth 8 -HalfHeight 12 -AngleDegrees 90

	$mainPen.Dispose()
	$detailPen.Dispose()

	$path = Join-Path $broodOutputDir "brood_center_glyph.png"
	Save-Bitmap -Bitmap $bitmap -Path $path

	$graphics.Dispose()
	$bitmap.Dispose()
}

function Build-BroodClawSproutsA {
	$asset = New-GlyphBitmap -Size $canvasSize
	$graphics = $asset.Graphics
	$bitmap = $asset.Bitmap

	$mainPen = New-RoundPen -Width 10
	$detailPen = New-RoundPen -Width 7

	$primary = @(
		@{ angle = -72; root = 208; tip = 244; curl = 16; width = 18 },
		@{ angle = 48;  root = 208; tip = 242; curl = 18; width = 17 },
		@{ angle = 176; root = 208; tip = 240; curl = 14; width = 16 },
		@{ angle = 286; root = 208; tip = 243; curl = 20; width = 18 }
	)
	foreach ($claw in $primary) {
		Draw-ClawSprout -Graphics $graphics -Pen $mainPen -AngleDegrees $claw.angle -RootRadius $claw.root -TipRadius $claw.tip -CurlDegrees $claw.curl -WidthDegrees $claw.width
	}

	$secondary = @(
		@{ angle = -8;  root = 206; tip = 228; curl = 10; width = 13 },
		@{ angle = 118; root = 206; tip = 226; curl = 9;  width = 12 },
		@{ angle = 228; root = 206; tip = 227; curl = 11; width = 12 }
	)
	foreach ($claw in $secondary) {
		Draw-ClawSprout -Graphics $graphics -Pen $detailPen -AngleDegrees $claw.angle -RootRadius $claw.root -TipRadius $claw.tip -CurlDegrees $claw.curl -WidthDegrees $claw.width
	}

	foreach ($angle in @(-90, 0, 90, 180)) {
		$graphics.DrawArc($detailPen, 256 - 220, 256 - 220, 440, 440, $angle - 6, 12)
	}

	$mainPen.Dispose()
	$detailPen.Dispose()

	$path = Join-Path $broodOutputDir "brood_claw_sprouts_a.png"
	Save-Bitmap -Bitmap $bitmap -Path $path

	$graphics.Dispose()
	$bitmap.Dispose()
}

function Build-BroodClawSproutsB {
	$asset = New-GlyphBitmap -Size $canvasSize
	$graphics = $asset.Graphics
	$bitmap = $asset.Bitmap

	$mainPen = New-RoundPen -Width 11
	$detailPen = New-RoundPen -Width 8

	$primary = @(
		@{ angle = -78; root = 208; tip = 266; curl = 24; width = 20 },
		@{ angle = 38;  root = 208; tip = 262; curl = 26; width = 19 },
		@{ angle = 166; root = 208; tip = 258; curl = 21; width = 18 },
		@{ angle = 282; root = 208; tip = 264; curl = 28; width = 20 }
	)
	foreach ($claw in $primary) {
		Draw-ClawSprout -Graphics $graphics -Pen $mainPen -AngleDegrees $claw.angle -RootRadius $claw.root -TipRadius $claw.tip -CurlDegrees $claw.curl -WidthDegrees $claw.width
	}

	$secondary = @(
		@{ angle = -18; root = 206; tip = 238; curl = 16; width = 14 },
		@{ angle = 110; root = 206; tip = 236; curl = 15; width = 13 },
		@{ angle = 222; root = 206; tip = 237; curl = 17; width = 13 }
	)
	foreach ($claw in $secondary) {
		Draw-ClawSprout -Graphics $graphics -Pen $detailPen -AngleDegrees $claw.angle -RootRadius $claw.root -TipRadius $claw.tip -CurlDegrees $claw.curl -WidthDegrees $claw.width
	}

	foreach ($angle in @(-90, 0, 90, 180)) {
		$graphics.DrawArc($detailPen, 256 - 224, 256 - 224, 448, 448, $angle - 7, 14)
	}

	$mainPen.Dispose()
	$detailPen.Dispose()

	$path = Join-Path $broodOutputDir "brood_claw_sprouts_b.png"
	Save-Bitmap -Bitmap $bitmap -Path $path

	$graphics.Dispose()
	$bitmap.Dispose()
}

function Build-SparkOuterRing {
	$asset = New-GlyphBitmap -Size $canvasSize
	$graphics = $asset.Graphics
	$bitmap = $asset.Bitmap

	$mainPen = New-RoundPen -Width 8
	$detailPen = New-RoundPen -Width 6

	Draw-ArcRing -Graphics $graphics -Pen $mainPen -Radius 188 -ArcCount 6 -ArcSweep 32 -StartOffsetDegrees -16
	Draw-ArcRing -Graphics $graphics -Pen $detailPen -Radius 168 -ArcCount 6 -ArcSweep 18 -StartOffsetDegrees 12

	foreach ($angle in @(-90, 0, 90, 180)) {
		Draw-Diamond -Graphics $graphics -Pen $detailPen -Distance 214 -HalfWidth 10 -HalfHeight 7 -AngleDegrees $angle
	}
	foreach ($angle in @(-60, 60, 120, 240, 300)) {
		Draw-Tick -Graphics $graphics -Pen $detailPen -InnerRadius 198 -OuterRadius 212 -AngleDegrees $angle
	}

	$mainPen.Dispose()
	$detailPen.Dispose()

	$path = Join-Path $sparkOutputDir "spark_outer_ring.png"
	Save-Bitmap -Bitmap $bitmap -Path $path

	$graphics.Dispose()
	$bitmap.Dispose()
}

function Build-SparkInnerRing {
	$asset = New-GlyphBitmap -Size $canvasSize
	$graphics = $asset.Graphics
	$bitmap = $asset.Bitmap

	$mainPen = New-RoundPen -Width 7
	$detailPen = New-RoundPen -Width 5

	Draw-ArcRing -Graphics $graphics -Pen $mainPen -Radius 118 -ArcCount 8 -ArcSweep 17 -StartOffsetDegrees -8
	Draw-ArcRing -Graphics $graphics -Pen $detailPen -Radius 96 -ArcCount 4 -ArcSweep 20 -StartOffsetDegrees 25

	foreach ($angle in @(-90, -30, 30, 90, 150, 210)) {
		Draw-Tick -Graphics $graphics -Pen $detailPen -InnerRadius 126 -OuterRadius 138 -AngleDegrees $angle
	}
	foreach ($angle in @(0, 120, 240)) {
		Draw-Diamond -Graphics $graphics -Pen $detailPen -Distance 142 -HalfWidth 7 -HalfHeight 5 -AngleDegrees $angle
	}

	$mainPen.Dispose()
	$detailPen.Dispose()

	$path = Join-Path $sparkOutputDir "spark_inner_ring.png"
	Save-Bitmap -Bitmap $bitmap -Path $path

	$graphics.Dispose()
	$bitmap.Dispose()
}

function Build-SparkCenterGlyph {
	$asset = New-GlyphBitmap -Size $canvasSize
	$graphics = $asset.Graphics
	$bitmap = $asset.Bitmap

	$mainPen = New-RoundPen -Width 7
	$detailPen = New-RoundPen -Width 5

	Draw-Diamond -Graphics $graphics -Pen $mainPen -Distance 0 -HalfWidth 16 -HalfHeight 22 -AngleDegrees 0
	foreach ($angle in @(-90, 0, 90, 180)) {
		Draw-Tick -Graphics $graphics -Pen $detailPen -InnerRadius 28 -OuterRadius 46 -AngleDegrees $angle
	}
	foreach ($angle in @(-45, 45, 135, 225)) {
		Draw-Tick -Graphics $graphics -Pen $detailPen -InnerRadius 22 -OuterRadius 34 -AngleDegrees $angle
	}
	$graphics.DrawArc($detailPen, 226, 226, 60, 60, -30, 60)
	$graphics.DrawArc($detailPen, 226, 226, 60, 60, 150, 60)

	$mainPen.Dispose()
	$detailPen.Dispose()

	$path = Join-Path $sparkOutputDir "spark_center_glyph.png"
	Save-Bitmap -Bitmap $bitmap -Path $path

	$graphics.Dispose()
	$bitmap.Dispose()
}

Build-BroodOuterRing
Build-BroodInnerRing
Build-BroodCenterGlyph
Build-BroodClawSproutsA
Build-BroodClawSproutsB
Build-SparkOuterRing
Build-SparkInnerRing
Build-SparkCenterGlyph

Write-Output "Generated summon sigil assets in $outputDir"
Write-Output "Generated brood sigil assets in $broodOutputDir"
Write-Output "Generated spark sigil assets in $sparkOutputDir"
