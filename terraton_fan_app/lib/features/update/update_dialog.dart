// lib/features/update/update_dialog.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/core/update/app_update_service.dart';
import 'package:terraton_fan_app/shared/theme.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});

  static Future<void> show(BuildContext context, UpdateInfo info) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: kSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) => UpdateDialog(info: info),
      );

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { idle, downloading, installing, error }

class _UpdateDialogState extends State<UpdateDialog> {
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  String? _errorMsg;

  Future<void> _startDownload() async {
    setState(() { _phase = _Phase.downloading; _progress = 0; });

    final file = await AppUpdateService.downloadUpdate(
      (p) { if (mounted) setState(() => _progress = p); },
      expectedSha256: widget.info.apkSha256,
    );

    if (!mounted) return;
    if (file == null) {
      setState(() {
        _phase = _Phase.error;
        _errorMsg = 'Download failed or the file was corrupted. '
            'Check your connection and try again.';
      });
      return;
    }

    setState(() => _phase = _Phase.installing);
    final installError = await AppUpdateService.installUpdate(file);
    if (!mounted) return;
    if (installError != null) {
      setState(() { _phase = _Phase.error; _errorMsg = installError; });
      return;
    }
    // Installer opened — OS takes over; dismiss the sheet.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: kHairlineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: kYellowFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kYellowBorder),
                ),
                child: const Icon(Icons.system_update_rounded, color: kYellow, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Update Available',
                        style: GoogleFonts.manrope(
                          fontSize: 18, fontWeight: FontWeight.w700, color: kText,
                        )),
                    Text(
                      'v${widget.info.localVersion} → v${widget.info.version}',
                      style: GoogleFonts.manrope(fontSize: 13, color: kTextMut),
                    ),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 20),

            if (_phase == _Phase.idle) ...[
              Text(
                'A new version of the Terraton app is ready to install.',
                style: GoogleFonts.manrope(fontSize: 14, color: kTextMut, height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kTextMut,
                      side: const BorderSide(color: kHairlineStrong),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Later',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => unawaited(_startDownload()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kYellow,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text('Update Now',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ] else if (_phase == _Phase.downloading) ...[
              Text('Downloading update…',
                  style: GoogleFonts.manrope(fontSize: 14, color: kTextMut)),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: kHairline,
                  valueColor: const AlwaysStoppedAnimation<Color>(kYellow),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.jetBrainsMono(fontSize: 12, color: kTextDim)),
            ] else if (_phase == _Phase.installing) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(color: kYellow, strokeWidth: 2),
                ),
              ),
              Center(
                child: Text('Opening installer…',
                    style: GoogleFonts.manrope(fontSize: 14, color: kTextMut)),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Text(_errorMsg ?? 'Something went wrong.',
                  style: GoogleFonts.manrope(fontSize: 14, color: kRed, height: 1.5)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kTextMut,
                    side: const BorderSide(color: kHairlineStrong),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Dismiss',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
