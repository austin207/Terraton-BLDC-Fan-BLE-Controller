// Generates assets/icon/icon.png — the Terraton 3-blade fan logo.
// Run: flutter test test/generate_icon_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('generate launcher icon PNG', (tester) async {
    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(painter: _IconPainter()),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // 200 * 5.12 = 1024 px
    final image = await boundary.toImage(pixelRatio: 5.12);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final outDir = Directory('${Directory.current.path}/assets/icon');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    File('${outDir.path}/icon.png').writeAsBytesSync(pngBytes);
  });
}

// Draws the Terraton logo: blue rounded square + 3-blade ceiling fan propeller.
class _IconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // ── Blue rounded square background ───────────────────────────────────────
    final bgPaint = Paint()..color = const Color(0xFF1A56A0);
    final bgRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(w * 0.23),
    );
    canvas.drawRRect(bgRRect, bgPaint);

    // ── White 3-blade ceiling fan propeller ──────────────────────────────────
    // R = outer radius of blade tip from centre.
    // The blade path is defined pointing UPWARD (–Y), then rotated ×3 by 120°.
    final R = w * 0.36; // 72 px on a 200-px canvas → fills icon nicely
    final hubR = R * 0.11; // small centre hub

    final bladePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(i * 2 * math.pi / 3);

      // One blade, pointing in the –Y direction.
      // Leading edge = RIGHT side (sweeps outward clockwise).
      // Trailing edge = LEFT side (more concave, swept-back look).
      final path = Path()
        // Start: right side of hub attachment
        ..moveTo(R * 0.10, -R * 0.12)

        // Leading edge: sweeps right as the blade goes up toward tip
        ..cubicTo(
          R * 0.32, -R * 0.22, // cp1
          R * 0.50, -R * 0.58, // cp2
          R * 0.36, -R * 0.88, // near tip, right side
        )

        // Rounded tip
        ..cubicTo(
          R * 0.24, -R * 0.99, // cp1
          -R * 0.04, -R * 0.99, // cp2
          -R * 0.18, -R * 0.88, // near tip, left side
        )

        // Trailing edge: concave, sweeps back to hub
        ..cubicTo(
          -R * 0.30, -R * 0.65, // cp1
          -R * 0.18, -R * 0.35, // cp2
          -R * 0.10, -R * 0.12, // left side of hub attachment
        )

        ..close();

      canvas.drawPath(path, bladePaint);
      canvas.restore();
    }

    // Centre hub circle
    canvas.drawCircle(Offset(cx, cy), hubR, bladePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
