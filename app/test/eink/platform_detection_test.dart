import 'package:butterfly/helpers/eink.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => EinkDisplay.enabled = false);
  tearDown(() => EinkDisplay.enabled = false);

  test('enables display mode when detector identifies Magic Pie', () async {
    await EinkDisplay.initialize(detect: () async => true);

    expect(EinkDisplay.enabled, isTrue);
  });

  test('stays disabled for an unknown device or null result', () async {
    await EinkDisplay.initialize(detect: () async => false);
    expect(EinkDisplay.enabled, isFalse);

    EinkDisplay.enabled = true;
    await EinkDisplay.initialize(detect: () async => null);
    expect(EinkDisplay.enabled, isFalse);
  });

  test('channel errors safely reset display mode', () async {
    for (final error in <Object>[
      MissingPluginException(),
      PlatformException(code: 'unavailable'),
      StateError('unexpected channel response'),
    ]) {
      EinkDisplay.enabled = true;
      await EinkDisplay.initialize(detect: () async => throw error);
      expect(
        EinkDisplay.enabled,
        isFalse,
        reason: error.runtimeType.toString(),
      );
    }
  });
}
