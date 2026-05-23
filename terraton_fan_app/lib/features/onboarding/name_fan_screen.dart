// lib/features/onboarding/name_fan_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/brand_mark.dart';
import 'package:terraton_fan_app/shared/terraton_fan_icon.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class NameFanScreen extends ConsumerStatefulWidget {
  final FanDevice fan;
  const NameFanScreen({super.key, required this.fan});

  @override
  ConsumerState<NameFanScreen> createState() => _NameFanScreenState();
}

class _NameFanScreenState extends ConsumerState<NameFanScreen> {
  late final TextEditingController _ctrl;
  final _formKey = GlobalKey<FormState>();

  static final _nameRegex = RegExp(r'^[a-zA-Z0-9 ]+$');

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    if (v == null || v.trim().isEmpty) return 'Name cannot be empty';
    if (v.length > 30) return 'Max 30 characters';
    if (!_nameRegex.hasMatch(v)) return 'Alphanumeric characters and spaces only';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final fan = FanDevice()
      ..deviceId   = widget.fan.deviceId
      ..macAddress = widget.fan.macAddress
      ..model      = widget.fan.model
      ..fwVersion  = widget.fan.fwVersion
      ..addedAt    = widget.fan.addedAt
      ..nickname   = _ctrl.text.trim();
    await ref.read(fanRepositoryProvider).saveFan(fan);
    if (!mounted) return;
    ref.invalidate(savedFansProvider);
    if (mounted) {
      context.go(AppRoutes.control, extra: fan);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kText, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: BrandMark(height: 40),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Fan icon with DETECTED badge
                Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 120, height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kYellow.withAlpha(20),
                          border: Border.all(color: kYellow.withAlpha(60), width: 1.5),
                          boxShadow: [const BoxShadow(color: kYellowGlow, blurRadius: 30)],
                        ),
                        child: const TerratonFanIcon(size: 68),
                      ),
                      Positioned(
                        bottom: -8, left: 0, right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: kGreen,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'DETECTED',
                              style: GoogleFonts.jetBrainsMono(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                Text('Name Your Fan',
                    style: GoogleFonts.manrope(
                      fontSize: 26, fontWeight: FontWeight.w700,
                      color: kText, letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(
                  '${widget.fan.model.isNotEmpty ? widget.fan.model : 'Fan'} detected! '
                  'Give it a nickname to easily identify it later.',
                  style: GoogleFonts.manrope(fontSize: 14, color: kTextMut, height: 1.55),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Label
                Text('YOUR NAME',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: kTextMut, letterSpacing: 2.2,
                    )),
                const SizedBox(height: 10),

                // Text field
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _ctrl,
                  builder: (_, value, __) => TextFormField(
                    controller: _ctrl,
                    maxLength: 30,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    autofocus: true,
                    style: GoogleFonts.manrope(
                      color: kText, fontSize: 18, fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Living Room Fan',
                      hintStyle: GoogleFonts.manrope(color: kTextDim, fontSize: 18),
                      filled: true,
                      fillColor: kCard,
                      counterText: '',
                      suffix: Text(
                        '${value.text.length}/30',
                        style: kMonoStyle(size: 11, color: kTextMut),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: value.text.isNotEmpty
                              ? kYellow.withAlpha(89)
                              : kHairlineStrong,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: value.text.isNotEmpty
                              ? kYellow.withAlpha(89)
                              : kHairlineStrong,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: kYellow, width: 1.5),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: kRed),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                    ),
                    validator: _validate,
                  ),
                ),

                const SizedBox(height: 16),

                // Requirements card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kGreen.withAlpha(20),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kGreen.withAlpha(60)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_rounded, color: kGreen, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Nickname Requirements',
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w700,
                                  color: kGreen, fontSize: 13,
                                )),
                            const SizedBox(height: 6),
                            _reqLine('Max 30 characters'),
                            _reqLine('Alphanumeric characters and spaces only'),
                            _reqLine('Nickname must not be empty'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Save button
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _ctrl,
                  builder: (_, value, __) => SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: value.text.trim().isNotEmpty ? _save : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: value.text.trim().isNotEmpty ? kYellow : kCard,
                        foregroundColor: value.text.trim().isNotEmpty ? Colors.black : kTextDim,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Save & Continue',
                              style: GoogleFonts.manrope(
                                fontSize: 16, fontWeight: FontWeight.w700,
                              )),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                Text('STEP 1 OF 1 · SETUP',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10, color: kTextDim, letterSpacing: 1.8,
                    ),
                    textAlign: TextAlign.center),
                    ],         // closes Form Column children
                  ),           // closes Form Column
                ),             // closes Form
              ),               // closes SingleChildScrollView
            ),                 // closes SafeArea
          ),                   // closes Expanded
        ],                     // closes outer Column children
      ),                       // closes outer Column (body)
    );
  }

  Widget _reqLine(String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4, height: 4,
          margin: const EdgeInsets.only(top: 7, right: 8),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: kGreen),
        ),
        Expanded(
          child: Text(text, style: GoogleFonts.manrope(fontSize: 13, color: kGreen)),
        ),
      ],
    ),
  );
}
