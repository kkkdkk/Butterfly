import 'package:butterfly/helpers/eink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => EinkDisplay.enabled = false);

  test('ink mapping is scoped, nested, and preserves white and alpha', () {
    const red = Color(0x80FF0000);
    EinkDisplay.enabled = true;

    expect(EinkDisplay.ink(red), red);
    EinkDisplay.paint(true, () {
      expect(EinkDisplay.ink(red), const Color(0x80000000));
      expect(EinkDisplay.ink(const Color(0xFFFFFFFF)), Colors.white);
      expect(EinkDisplay.ink(const Color(0x00FF0000)), const Color(0x00FF0000));
      EinkDisplay.paint(false, () => expect(EinkDisplay.ink(red), red));
      expect(EinkDisplay.ink(red), const Color(0x80000000));
    });
    expect(EinkDisplay.ink(red), red);
  });

  test('paint scope is restored when rendering throws', () {
    EinkDisplay.enabled = true;

    expect(
      () => EinkDisplay.paint(true, () => throw StateError('paint failed')),
      throwsStateError,
    );
    expect(EinkDisplay.isPainting, isFalse);
  });

  test('initialize is controllable and failures safely disable mode', () async {
    await EinkDisplay.initialize(detect: () async => true);
    expect(EinkDisplay.enabled, isTrue);

    await EinkDisplay.initialize(
      detect: () => Future<bool?>.error(StateError('channel failed')),
    );
    expect(EinkDisplay.enabled, isFalse);
  });

  test('paper mapping keeps transparent pixels and provides white paper', () {
    EinkDisplay.enabled = true;
    EinkDisplay.paint(true, () {
      expect(EinkDisplay.paper(const Color(0xFFF0D0F0)), Colors.white);
      expect(
        EinkDisplay.paper(const Color(0x00301050)),
        const Color(0x00301050),
      );
    });
  });

  test('dark paper keeps white pen and maps colored foreground to white', () {
    EinkDisplay.enabled = true;
    EinkDisplay.paint(true, () {
      EinkDisplay.preparePaper(const Color(0xFF301050));
      expect(EinkDisplay.paper(const Color(0xFF301050)), Colors.black);
      expect(EinkDisplay.ink(const Color(0xFFFFFFFF)), Colors.white);
      expect(EinkDisplay.ink(const Color(0xFFFF0000)), Colors.white);
      expect(EinkDisplay.ink(const Color(0xFF000000)), Colors.white);
    });
  });
}
