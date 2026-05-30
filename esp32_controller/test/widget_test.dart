import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:esp32_controller/ble_payload.dart';
import 'package:esp32_controller/main.dart';

void main() {
  group('encodeBleControlPacket', () {
    test('encodes values in expected order', () {
      final packet = encodeBleControlPacket(
        category: 1,
        subMode: 2,
        red: 10,
        green: 20,
        blue: 30,
        volume: 40,
        showPeak: true,
        gain: 100,
        bass: 110,
        treble: 120,
      );

      expect(packet, equals([1, 2, 10, 20, 30, 40, 1, 100, 110, 120]));
    });

    test('clamps out-of-range inputs', () {
      final packet = encodeBleControlPacket(
        category: -5,
        subMode: 99,
        red: -1,
        green: 999,
        blue: 256,
        volume: 101,
        showPeak: false,
        gain: -10,
        bass: 256,
        treble: 400,
      );

      expect(packet, equals([0, 2, 0, 255, 255, 100, 0, 0, 255, 255]));
    });
  });

  testWidgets('SimpleColorWheel renders and is disabled via IgnorePointer', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SimpleColorWheel(
            color: Color.fromARGB(255, 255, 0, 0),
            enabled: false,
            onColorChanged: _noopColorChanged,
          ),
        ),
      ),
    );

    final ignorePointerFinder = find.descendant(
      of: find.byType(SimpleColorWheel),
      matching: find.byType(IgnorePointer),
    );
    final ignorePointer = tester.widget<IgnorePointer>(ignorePointerFinder);
    expect(ignorePointer.ignoring, isTrue);
    expect(
      find.descendant(
        of: find.byType(SimpleColorWheel),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });
}

void _noopColorChanged(Color _) {}
