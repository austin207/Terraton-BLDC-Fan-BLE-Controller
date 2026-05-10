// Generates assets/icon/icon.png from the Terraton logo widget.
// Run: flutter test test/generate_icon_test.dart
import 'dart:io';
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
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A56A0),
                  borderRadius: BorderRadius.circular(46),
                ),
                child: const Icon(
                  Icons.wind_power_rounded,
                  color: Colors.white,
                  size: 110,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // pixelRatio 5.12 → 200 * 5.12 = 1024 px
    final image = await boundary.toImage(pixelRatio: 5.12);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final outDir = Directory('${Directory.current.path}/assets/icon');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    File('${outDir.path}/icon.png').writeAsBytesSync(pngBytes);
  });
}
