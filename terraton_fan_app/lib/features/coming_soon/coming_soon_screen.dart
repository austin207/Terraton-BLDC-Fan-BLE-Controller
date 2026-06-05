// lib/features/coming_soon/coming_soon_screen.dart
//
// Placeholder shown when a user selects an appliance type that Terraton does
// not support yet (water filtration, air purification, energy / storage).
// Reached from ApplianceTypesScreen when the category is flagged comingSoon
// in appliances.yaml — keeps these types out of the fan pairing flow.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/models/appliance.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class ComingSoonScreen extends StatelessWidget {
  /// The appliance type the user tapped. Null renders a generic message.
  final ApplianceType? applianceType;
  const ComingSoonScreen({super.key, this.applianceType});

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
    final type = applianceType;
    final name = type?.displayName ?? 'This device';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kText, size: 20),
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
        title: Text(
          type?.pluralLabel ?? 'Coming Soon',
          style: GoogleFonts.manrope(
            fontSize: 16, fontWeight: FontWeight.w700, color: kText,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Type icon with yellow glow ring.
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kYellow.withAlpha(20),
                  border: Border.all(color: kYellow.withAlpha(50)),
                  boxShadow: const [BoxShadow(color: kYellowGlow, blurRadius: 40)],
                ),
                child: Center(
                  child: type != null
                      ? Image.asset(
                          type.iconPath,
                          width: 56, height: 56,
                          color: kYellow,
                          colorBlendMode: BlendMode.srcIn,
                          errorBuilder: (_, __, ___) => Icon(
                            _fallbackIcon(type.id), size: 52, color: kYellow,
                          ),
                        )
                      : const Icon(Icons.hourglass_top_rounded, size: 52, color: kYellow),
                ),
              ),
              const SizedBox(height: 28),

              // COMING SOON badge.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: kYellowFill,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: kYellowBorderHi),
                ),
                child: Text(
                  'COMING SOON',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: kYellow, letterSpacing: 2.4,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              Text(
                name,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 24, fontWeight: FontWeight.w700,
                  color: kText, letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "$name support is on the way. We're putting the finishing "
                'touches on it — check back in a future update.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 14, height: 1.55, color: kTextMut,
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go(AppRoutes.home),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kYellow,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Got it',
                    style: GoogleFonts.manrope(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
