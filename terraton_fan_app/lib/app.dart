// lib/app.dart
import 'package:flutter/material.dart';
import 'package:terraton_fan_app/shared/router.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class TerratorApp extends StatelessWidget {
  const TerratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Terraton Fan',
      theme: buildAppTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
