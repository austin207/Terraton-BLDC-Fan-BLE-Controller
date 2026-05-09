// lib/features/onboarding/name_fan_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
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
    final fan = widget.fan..nickname = _ctrl.text.trim();
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
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
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade100,
                          border: Border.all(color: Colors.grey.shade200, width: 1.5),
                        ),
                        child: const Icon(Icons.wind_power, size: 60, color: kPrimary),
                      ),
                      Positioned(
                        bottom: -6,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1DB954),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'DETECTED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                const Text(
                  'Name Your Fan',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Terraton X1 detected! Give it a nickname to easily identify it later.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),

                // Text field with live character counter
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _ctrl,
                  builder: (context, value, _) {
                    return TextFormField(
                      controller: _ctrl,
                      maxLength: 30,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                          Text(
                            '$currentLength / ${maxLength ?? 30}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                      decoration: InputDecoration(
                        hintText: 'e.g., Living Room Fan',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: kPrimary, width: 1.5),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.red),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      validator: _validate,
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Nickname requirements card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF8F0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1DB954).withAlpha(80)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline, color: Color(0xFF1DB954), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Nickname Requirements',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0D6E38),
                                fontSize: 14,
                              ),
                            ),
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

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'Save & Continue',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reqLine(String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: TextStyle(color: Colors.green.shade700, fontSize: 13)),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.green.shade800))),
          ],
        ),
      );
}
