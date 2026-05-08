// lib/features/control/connection_banner.dart
import 'package:flutter/material.dart';
import 'package:terraton_fan_app/core/ble/ble_connection_state.dart';

class ConnectionBanner extends StatelessWidget {
  final BleConnectionState state;
  final VoidCallback onRetry;

  const ConnectionBanner({super.key, required this.state, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    Color bg;
    String label;
    bool showRetry = false;

    switch (state) {
      case BleConnectionState.connected:
        bg = Colors.green.shade600;
        label = 'Connected';
      case BleConnectionState.connecting:
      case BleConnectionState.scanning:
        bg = Colors.amber.shade700;
        label = 'Connecting…';
      case BleConnectionState.disconnected:
        bg = Colors.red.shade600;
        label = 'Disconnected';
        showRetry = true;
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          if (showRetry) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onRetry,
              child: const Text('Tap to retry',
                  style: TextStyle(color: Colors.white, decoration: TextDecoration.underline)),
            ),
          ],
        ],
      ),
    );
  }
}
