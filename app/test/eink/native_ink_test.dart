import 'dart:async';

import 'package:butterfly/helpers/native_ink.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final frame = Uint8List.fromList([137, 80, 78, 71]);
  late NativeInkSession session;

  Future<Uint8List?> capture(double dpr) async => frame;

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
    await session.prepare(
      const Rect.fromLTWH(0, 0, 80, 90),
      1,
      captureFrame: capture,
    );
    session.addDirty(const Rect.fromLTWH(10, 20, 30, 40));
    final presented = session.presentAfterFrame();
    expect(calls.map((call) => call.method), ['prepare']);
    await tester.pump();
    await presented;
    expect(calls.map((call) => call.method), ['prepare', 'present']);
    expect(calls.last.arguments, {
      'left': 10.0,
      'top': 20.0,
      'width': 30.0,
      'height': 40.0,
      'image': frame,
    });
  });

  testWidgets('dispose cancels queued frame presentation', (tester) async {
    await session.prepare(
      const Rect.fromLTWH(0, 0, 80, 90),
      1,
      captureFrame: capture,
    );
    session.addDirty(const Rect.fromLTWH(10, 20, 30, 40));
    final presented = session.presentAfterFrame();
    await session.dispose();
    await tester.pump();
    await presented;
    expect(calls.map((call) => call.method), ['prepare', 'dispose']);
  });

  testWidgets('a new pending stroke prevents clearing the previous overlay', (
    tester,
  ) async {
    await session.prepare(
      const Rect.fromLTWH(0, 0, 80, 90),
      1,
      captureFrame: capture,
    );
    session.addDirty(const Rect.fromLTWH(10, 20, 30, 40));
    var ready = true;
    final presented = session.presentAfterFrame(isReady: () => ready);
    ready = false;
    await tester.pump();
    await presented;
    expect(calls.map((call) => call.method), ['prepare']);
    expect(session.active, isTrue);
  });

  testWidgets('unchanged viewport never requests a whole canvas refresh', (
    tester,
  ) async {
    await session.prepare(const Rect.fromLTWH(0, 0, 80, 90), 1);
    await session.presentAfterFrame();
    expect(calls.map((call) => call.method), ['prepare']);
  });

  testWidgets('dirty rectangles merge, clip and scale to physical pixels', (
    tester,
  ) async {
    await session.prepare(
      const Rect.fromLTWH(4, 50, 80, 90),
      1.25,
      captureFrame: capture,
    );
    session.addDirty(const Rect.fromLTWH(-10, 20, 30, 20));
    session.addDirty(const Rect.fromLTWH(10, 30, 20, 30));
    final presented = session.presentAfterFrame();
    await tester.pump();
    await presented;
    expect(calls.last.arguments, {
      'left': 0.0,
      'top': 25.0,
      'width': 37.5,
      'height': 50.0,
      'image': frame,
    });
  });

  testWidgets('capture failure disposes native preview', (tester) async {
    await session.prepare(
      const Rect.fromLTWH(0, 0, 80, 90),
      1,
      captureFrame: (_) async => null,
    );
    session.addDirty(const Rect.fromLTWH(10, 20, 30, 40));

    final presented = session.presentAfterFrame();
    await tester.pump();
    await presented;

    expect(calls.map((call) => call.method), ['prepare', 'dispose']);
    expect(session.active, isFalse);
  });

  testWidgets('dispose during capture cannot present a stale frame', (
    tester,
  ) async {
    final captured = Completer<Uint8List?>();
    await session.prepare(
      const Rect.fromLTWH(0, 0, 80, 90),
      1,
      captureFrame: (_) => captured.future,
    );
    session.addDirty(const Rect.fromLTWH(10, 20, 30, 40));
    final presented = session.presentAfterFrame();
    await tester.pump();

    final disposed = session.dispose();
    captured.complete(frame);
    await presented;
    await disposed;

    expect(calls.map((call) => call.method), ['prepare', 'dispose']);
  });

  testWidgets('new stroke during capture keeps and merges dirty bounds', (
    tester,
  ) async {
    final firstCapture = Completer<Uint8List?>();
    var captures = 0;
    await session.prepare(
      const Rect.fromLTWH(0, 0, 80, 90),
      1,
      captureFrame: (_) {
        captures++;
        return captures == 1 ? firstCapture.future : Future.value(frame);
      },
    );
    var ready = true;
    session.addDirty(const Rect.fromLTWH(10, 20, 20, 20));
    final firstPresent = session.presentAfterFrame(isReady: () => ready);
    await tester.pump();

    ready = false;
    session.addDirty(const Rect.fromLTWH(25, 35, 20, 20));
    firstCapture.complete(frame);
    await firstPresent;
    expect(calls.map((call) => call.method), ['prepare']);

    ready = true;
    final secondPresent = session.presentAfterFrame(isReady: () => ready);
    await tester.pump();
    await secondPresent;
    expect(calls.map((call) => call.method), ['prepare', 'present']);
    expect(calls.last.arguments, {
      'left': 10.0,
      'top': 20.0,
      'width': 35.0,
      'height': 35.0,
      'image': frame,
    });
  });

  testWidgets('late capture error cannot dispose a newer session', (
    tester,
  ) async {
    final firstCapture = Completer<Uint8List?>();
    await session.prepare(
      const Rect.fromLTWH(0, 0, 80, 90),
      1,
      captureFrame: (_) => firstCapture.future,
    );
    session.addDirty(const Rect.fromLTWH(10, 20, 30, 40));
    final firstPresent = session.presentAfterFrame();
    await tester.pump();

    await session.prepare(
      const Rect.fromLTWH(0, 0, 80, 90),
      1,
      captureFrame: capture,
    );
    firstCapture.completeError(StateError('stale capture'));
    await firstPresent;

    expect(calls.map((call) => call.method), ['prepare', 'prepare']);
    expect(session.active, isTrue);
  });

  testWidgets('failed present disposes the current native session', (
    tester,
  ) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeInkSession.channel,
      (call) async {
        calls.add(call);
        return call.method != 'present';
      },
    );
    await session.prepare(
      const Rect.fromLTWH(0, 0, 80, 90),
      1,
      captureFrame: capture,
    );
    session.addDirty(const Rect.fromLTWH(10, 20, 30, 40));

    final presented = session.presentAfterFrame();
    await tester.pump();
    await presented;

    expect(calls.map((call) => call.method), ['prepare', 'present', 'dispose']);
    expect(session.active, isFalse);
  });

  testWidgets('post-frame presentation schedules its capture frame', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    await session.prepare(
      const Rect.fromLTWH(0, 0, 80, 90),
      1,
      captureFrame: capture,
    );
    session.addDirty(const Rect.fromLTWH(10, 20, 30, 40));
    var callbackRan = false;
    tester.binding.addPostFrameCallback((_) {
      callbackRan = true;
      session.presentAfterFrame();
    });

    tester.binding.scheduleFrame();
    await tester.pump();
    expect(callbackRan, isTrue);
    expect(calls.map((call) => call.method), ['prepare']);
    await tester.pump();
    expect(calls.map((call) => call.method), ['prepare', 'present']);
  });
}
