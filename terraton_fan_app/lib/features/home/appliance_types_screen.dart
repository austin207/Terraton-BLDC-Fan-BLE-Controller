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
              'CHOOSE A TYPE',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: kTextMut, letterSpacing: 2.2,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: types.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) => ApplianceTypeCard(
                  applianceType: types[i],
                  subtitle: (cat?.comingSoon ?? false)
                      ? 'Coming soon'
                      : '${types[i].modelCount} models',
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

/// Full-width rectangular row for one [ApplianceType], styled to match the
/// home-screen category tiles (icon on the left, name + subtitle, chevron).
/// Animates the yellow gradient and glow on press.
class ApplianceTypeCard extends StatefulWidget {
  final ApplianceType applianceType;
  final String? subtitle;
  final VoidCallback onTap;

  const ApplianceTypeCard({
    super.key,
    required this.applianceType,
    required this.onTap,
    this.subtitle,
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
    final type = widget.applianceType;
    return Semantics(
      button: true,
      label: type.displayName,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _pressed ? kCardElev : kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _pressed ? kYellow.withAlpha(110) : kHairline,
            ),
            boxShadow: _pressed
                ? const [BoxShadow(color: kYellowGlow, blurRadius: 16, spreadRadius: -6)]
                : const [],
          ),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: kYellow.withAlpha(38),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kYellow.withAlpha(76)),
                ),
                child: Center(
                  child: Image.asset(
                    type.iconPath,
                    width: 20, height: 20,
                    color: kYellow,
                    colorBlendMode: BlendMode.srcIn,
                    errorBuilder: (_, __, ___) => Icon(
                      _fallbackIcon(type.id), size: 18, color: kYellow,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.displayName,
                      style: GoogleFonts.manrope(
                        fontSize: 17, fontWeight: FontWeight.w700,
                        color: kText, letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle!,
                        style: GoogleFonts.manrope(
                          fontSize: 12, color: kTextMut,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: kTextMut, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
