// Runs once per test file before testMain.
// Disables google_fonts network fetching so fonts are loaded from the bundled
// assets in assets/fonts/ instead of being downloaded from Google's CDN.
// This makes tests hermetic and fast in CI and offline environments.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
