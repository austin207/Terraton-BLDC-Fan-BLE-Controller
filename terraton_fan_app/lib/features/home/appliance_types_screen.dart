// lib/features/home/appliance_types_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/core/appliances/appliance_loader.dart';
import 'package:terraton_fan_app/models/appliance.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/theme.dart';

/// Displays all [ApplianceType]s within [category] as a 2-column grid.
/// If [category] is null, falls back to the 'fans' category from config.
class ApplianceTypesScreen extends StatelessWidget {
  final ApplianceCategory? category;
  const ApplianceTypesScreen({super.key, this.category});

  @override
  Widget build(BuildContext context) {
    final cat = category ?? ApplianceLoader.categoryById('fans');
    final types = cat?.types ?? const <ApplianceType>[];

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kText, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Select ${cat?.displayName ?? 'Fan'} Type',
          style: GoogleFonts.manrope(
            fontSize: 16, fontWeight: FontWeight.w700, color: kText,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CHOOSE A CATEGORY',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: kTextMut, letterSpacing: 2.2,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                itemCount: types.length,
                itemBuilder: (_, i) => ApplianceTypeCard(
                  applianceType: types[i],
                  // Non-fan categories aren't supported yet → show Coming Soon
                  // instead of dropping the user into the fan pairing flow.
                  onTap: () => unawaited(
                    (cat?.comingSoon ?? false)
                        ? context.push(AppRoutes.comingSoon, extra: types[i])
                        : context.push(AppRoutes.fans, extra: types[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card for one [ApplianceType] in the 2-column grid.
/// Animates scale and glow on press; tints the icon yellow when pressed.
class ApplianceTypeCard extends StatefulWidget {
  final ApplianceType applianceType;
  final VoidCallback onTap;

  const ApplianceTypeCard({
    super.key,
    required this.applianceType,
    required this.onTap,
  });

  @override
  State<ApplianceTypeCard> createState() => _ApplianceTypeCardState();
}

class _ApplianceTypeCardState extends State<ApplianceTypeCard> {
  bool _pressed = false;

  static IconData _fallbackIcon(String typeId) {
    if (typeId.contains('ro') || typeId.contains('uv') || typeId.contains('water')) {
      return Icons.water_drop_outlined;
    }
    if (typeId.contains('air') || typeId.contains('aqm')) {
      return Icons.air_outlined;
    }
    if (typeId.contains('solar') || typeId.contains('battery') ||
        typeId.contains('energy') || typeId.contains('power')) {
      return Icons.bolt_outlined;
    }
    return Icons.devices_other_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.applianceType.displayName,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: _pressed ? kCardElev : kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _pressed ? kYellow.withAlpha(110) : kHairline,
              ),
              boxShadow: _pressed
                  ? [const BoxShadow(color: kYellowGlow, blurRadius: 20, spreadRadius: -4)]
                  : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    color: _pressed
                        ? kYellow.withAlpha(38)
                        : kYellow.withAlpha(20),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _pressed
                          ? kYellow.withAlpha(100)
                          : kYellow.withAlpha(40),
                    ),
                  ),
                  child: Center(
                    child: Image.asset(
                      widget.applianceType.iconPath,
                      width: 32, height: 32,
                      color: _pressed ? kYellow : kTextMut,
                      colorBlendMode: BlendMode.srcIn,
                      errorBuilder: (_, __, ___) => Icon(
                        _fallbackIcon(widget.applianceType.id),
                        size: 28,
                        color: _pressed ? kYellow : kTextMut,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    widget.applianceType.displayName,
                    style: GoogleFonts.manrope(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: _pressed ? kText : kTextMut,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
