import 'dart:async';

import 'package:butterfly/helpers/native_ink.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  late NativeInkSession session;

  setUp(() {
    session = NativeInkSession();
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeInkSession.channel,
      (call) async {
        calls.add(call);
        return true;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeInkSession.channel,
      null,
    );
  });

  test('prepare sends logical bounds and DPR without double scaling', () async {
    expect(
      await session.prepare(const Rect.fromLTWH(4, 50, 800, 900), 1.25),
      isTrue,
    );
    expect(calls.single.method, 'prepare');
    expect(calls.single.arguments, {
      'left': 4.0,
      'top': 50.0,
      'width': 800.0,
      'height': 900.0,
      'dpr': 1.25,
    });
    expect(session.active, isTrue);
  });

  test('invalid bounds dispose instead of enabling native ink', () async {
    expect(await session.prepare(Rect.zero, 1), isFalse);
    expect(calls.single.method, 'dispose');
    expect(session.active, isFalse);
  });

  test('missing platform channel safely leaves Flutter as fallback', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeInkSession.channel,
      null,
    );
    expect(
      await session.prepare(const Rect.fromLTWH(0, 0, 80, 90), 1),
      isFalse,
    );
    expect(session.active, isFalse);
  });

  test(
    'late prepare completion cannot reactivate a disposed session',
    () async {
      final ready = Completer<bool>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeInkSession.channel,
        (call) async => call.method == 'prepare' ? ready.future : true,
      );
      final preparing = session.prepare(const Rect.fromLTWH(0, 0, 80, 90), 1);
      await session.dispose();
      ready.complete(true);
      expect(await preparing, isFalse);
      expect(session.active, isFalse);
    },
  );

  testWidgets('presentation waits for the final Flutter frame', (tester) async {
    await session.prepare(const Rect.fromLTWH(0, 0, 80, 90), 1);
    final presented = session.presentAfterFrame();
    expect(calls.map((call) => call.method), ['prepare']);
    await tester.pump();
    await presented;
    expect(calls.map((call) => call.method), ['prepare', 'present']);
  });

  testWidgets('dispose cancels queued frame presentation', (tester) async {
    await session.prepare(const Rect.fromLTWH(0, 0, 80, 90), 1);
    final presented = session.presentAfterFrame();
    await session.dispose();
    await tester.pump();
    await presented;
    expect(calls.map((call) => call.method), ['prepare', 'dispose']);
  });

  testWidgets('a new pending stroke prevents clearing the previous overlay', (
    tester,
  ) async {
    await session.prepare(const Rect.fromLTWH(0, 0, 80, 90), 1);
    var ready = true;
    final presented = session.presentAfterFrame(isReady: () => ready);
    ready = false;
    await tester.pump();
    await presented;
    expect(calls.map((call) => call.method), ['prepare']);
    expect(session.active, isTrue);
  });
}
