// lib/features/onboarding/profile_setup_screen.dart
// "What should we call you?" — shown on first launch after permissions.
// Matches profile.jsx exactly.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/core/storage/app_settings.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/brand_mark.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _ctrl = TextEditingController();

  bool get _valid => _ctrl.text.trim().length >= 2;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
    // Soft focus after mount (matches JSX setTimeout 200 ms)
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  final _focusNode = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_valid) return;
    final name = _ctrl.text.trim();
    await ref.read(userNameProvider.notifier).save(name);
    await AppSettings.markProfileSet();
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Top brand
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: BrandMark(height: 40),
              ),
            ),

            // Main content — vertically centred
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 48),

                    // User icon chip
                    Container(
                      width: 76, height: 76,
                      decoration: BoxDecoration(
                        color: const Color(0x1AFFEC00),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0x40FFEC00)),
                        boxShadow: const [BoxShadow(color: kYellowGlow, blurRadius: 40)],
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 38,
                        color: kYellow,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Headline
                    Text(
                      'What should\nwe call you?',
                      style: GoogleFonts.manrope(
                        fontSize: 32, fontWeight: FontWeight.w700,
                        color: kText, letterSpacing: -0.7, height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We\'ll personalize your home, devices and schedules around your name.',
                      style: GoogleFonts.manrope(fontSize: 14, color: kTextMut, height: 1.5),
                    ),

                    const SizedBox(height: 36),

                    // Label
                    Text('YOUR NAME',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: kTextMut, letterSpacing: 2.2,
                        )),
                    const SizedBox(height: 10),

                    // Input field
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _ctrl.text.isNotEmpty
                              ? const Color(0x59FFEC00)
                              : kHairlineStrong,
                          width: 1.5,
                        ),
                        boxShadow: _ctrl.text.isNotEmpty
                            ? const [BoxShadow(color: kYellowGlow, blurRadius: 24)]
                            : null,
                      ),
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focusNode,
                        maxLength: 32,
                        style: GoogleFonts.manrope(
                          fontSize: 18, fontWeight: FontWeight.w600, color: kText,
                        ),
                        cursorColor: kYellow,
                        decoration: InputDecoration(
                          hintText: 'Austin',
                          hintStyle: GoogleFonts.manrope(color: kTextDim, fontSize: 18),
                          counterText: '',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(18),
                        ),
                        onSubmitted: (_) => _continue(),
                      ),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),

            // Footer CTA
            Padding(
              padding: EdgeInsets.fromLTRB(
                24, 16, 24,
                MediaQuery.viewInsetsOf(context).bottom > 0 ? 12 : 0,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    color: _valid ? kYellow : kCard,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: _valid
                        ? const [BoxShadow(color: kYellowGlow, blurRadius: 28)]
                        : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _valid ? () => unawaited(_continue()) : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Continue',
                              style: GoogleFonts.manrope(
                                fontSize: 15, fontWeight: FontWeight.w700,
                                color: _valid ? Colors.black : kTextDim,
                                letterSpacing: 0.04,
                              )),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right_rounded,
                              size: 20,
                              color: _valid ? Colors.black : kTextDim),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Step indicator — pinned at the very bottom
            Padding(
              padding: EdgeInsets.fromLTRB(
                24, 12, 24,
                MediaQuery.viewInsetsOf(context).bottom > 0 ? 12 : 32,
              ),
              child: Center(
                child: Text('STEP 1 OF 1 · SETUP',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10, color: kTextDim, letterSpacing: 1.8,
                    )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

