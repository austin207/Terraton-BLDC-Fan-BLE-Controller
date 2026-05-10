// lib/features/home/fan_card.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terraton_fan_app/core/providers.dart';
import 'package:terraton_fan_app/models/fan_device.dart';
import 'package:terraton_fan_app/shared/app_routes.dart';
import 'package:terraton_fan_app/shared/fan_icon.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class FanCard extends ConsumerWidget {
  final FanDevice fan;
  const FanCard({super.key, required this.fan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(AppRoutes.control, extra: fan),
        onLongPress: () => _showOptions(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: kPrimary.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const FanIcon(size: 28, color: kPrimary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fan.nickname,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    if (fan.model.isNotEmpty)
                      Text(fan.model, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF94A3B8),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Disconnected',
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_outlined, size: 20),
              ),
              title: const Text('Rename Fan', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Change the display name of this device'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _showRenameDialog(context, ref);
              },
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade700),
              ),
              title: Text('Remove Device',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red.shade700)),
              subtitle: const Text('Unpair and remove from your account'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _confirmDelete(context, ref);
              },
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text(
                'Cancel',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              onTap: () => Navigator.of(sheetCtx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RenameSheet(initialName: fan.nickname),
    ).then((name) async {
      if (name != null && name.isNotEmpty && context.mounted) {
        await ref.read(fanRepositoryProvider).renameFan(fan.deviceId, name);
        if (context.mounted) ref.invalidate(savedFansProvider);
      }
    });
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remove Device?'),
        content: Text('Remove "${fan.nickname}" from your device?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed == true && context.mounted) {
        await ref.read(fanRepositoryProvider).deleteFan(fan.deviceId);
        if (context.mounted) ref.invalidate(savedFansProvider);
      }
    });
  }
}

class _RenameSheet extends StatefulWidget {
  final String initialName;
  const _RenameSheet({required this.initialName});

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _ctrl;
  final _formKey = GlobalKey<FormState>();
  static final _nameRegex = RegExp(r'^[a-zA-Z0-9 ]+$');

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName);
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20,
        right: 20,
        top: 12,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Rename Fan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ctrl,
              builder: (context, value, _) {
                return TextFormField(
                  controller: _ctrl,
                  maxLength: 30,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  autofocus: true,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      const SizedBox.shrink(),
                  decoration: InputDecoration(
                    hintText: 'Living Room Fan',
                    hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    suffixText: '${value.text.length} / 30',
                    suffixStyle: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kPrimary, width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFEF4444)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  validator: _validate,
                );
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    Navigator.of(context).pop(_ctrl.text.trim());
                  }
                },
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 15, color: Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
