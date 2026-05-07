// lib/features/onboarding/name_fan_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../models/fan_device.dart';

class NameFanScreen extends ConsumerStatefulWidget {
  final FanDevice fan;
  const NameFanScreen({super.key, required this.fan});

  @override
  ConsumerState<NameFanScreen> createState() => _NameFanScreenState();
}

class _NameFanScreenState extends ConsumerState<NameFanScreen> {
  late final TextEditingController _ctrl;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final initial = widget.fan.model.isNotEmpty ? widget.fan.model : 'Terraton Fan';
    _ctrl = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    if (v == null || v.trim().isEmpty) return 'Name cannot be empty';
    if (v.length > 30) return 'Max 30 characters';
    if (!RegExp(r'^[a-zA-Z0-9 ]+$').hasMatch(v)) {
      return 'Alphanumeric characters and spaces only';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final fan = widget.fan..nickname = _ctrl.text.trim();
    await ref.read(fanRepositoryProvider).saveFan(fan);
    ref.invalidate(savedFansProvider);
    ref.read(activeFanProvider.notifier).set(fan);
    if (mounted) {
      context.go('/control', extra: fan);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Name Your Fan')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Give your fan a nickname:',
                  style: TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ctrl,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'Fan Nickname',
                  border: OutlineInputBorder(),
                ),
                validator: _validate,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
