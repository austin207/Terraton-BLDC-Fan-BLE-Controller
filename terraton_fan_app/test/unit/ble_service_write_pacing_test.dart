// test/unit/ble_service_write_pacing_test.dart
//
// Proves that BleServiceImpl.writeFrame goes through the pacing WriteQueue
// rather than straight at the characteristic.
//
// Why this matters: _onMode's "switch out of Reverse into Nature/Smart" path
// is the one tap that must send more than one frame (firmware's NATURE/SMART
// branches never clear `direction`, and get_mc_state() tests `direction`
// first, so the fan has to be brought forward before the mode is set). Both
// frames were fired unawaited in a single synchronous turn straight into
// writeWithoutResponse, landing in the same BLE connection interval. The
// BLE60 only flushes to the MCU on \r\n and the MCU parses one request frame
// at a time, so the second frame was lost — the fan exited reverse and
// returned to its previous speed, and no mode was ever set.
//
// No characteristic is connected here, so every write fails with the usual
// StateError. That is precisely what makes the ordering observable without a
// BLE stack: the *timing of the failures* shows whether the writes were
// serialised and spaced or issued together.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraton_fan_app/core/ble/ble_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'two frames written in one synchronous turn are serialised and spaced, '
      'not issued into the same connection interval', () {
    fakeAsync((async) {
      final svc = BleServiceImpl();
      final settledAt = <int>[];

      // The exact call shape of the Reverse → Nature tap in _onMode.
      unawaited(svc
          .writeFrame([0x55, 0xAA, 0x06, 0x21, 0x01, 0x03, 0x2A])
          .catchError((Object _) => settledAt.add(async.elapsed.inMilliseconds)));
      unawaited(svc
          .writeFrame([0x55, 0xAA, 0x06, 0x21, 0x01, 0x02, 0x29])
          .catchError((Object _) => settledAt.add(async.elapsed.inMilliseconds)));

      async.elapse(const Duration(seconds: 1));

      expect(settledAt.length, 2,
          reason: 'both frames must be attempted — the queue must not drop or '
              'stall a frame behind a failing one');
      expect(
        settledAt[1] - settledAt[0],
        greaterThanOrEqualTo(50),
        reason: 'the second frame must be held back from the first. Before the '
            'queue was wired in, both writes were issued in the same turn and '
            'the fan only ever acted on the first — the mode frame after an '
            'exit-reverse frame was silently lost.',
      );

      unawaited(svc.dispose());
      async.elapse(const Duration(seconds: 1));
    });
  });
}
