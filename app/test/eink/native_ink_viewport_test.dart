import 'dart:async';

import 'package:archive/archive.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/current_index.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/helpers/eink.dart';
import 'package:butterfly/helpers/native_ink.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly/views/native_ink.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:material_leap/material_leap.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

class _NativeInkHarness {
  final DocumentBloc bloc;
  final CurrentIndexCubit currentIndexCubit;
  final TransformCubit transformCubit;
  final WindowCubit windowCubit;

  const _NativeInkHarness(
    this.bloc,
    this.currentIndexCubit,
    this.transformCubit,
    this.windowCubit,
  );

  Future<void> close() async {
    await bloc.close();
    await currentIndexCubit.close();
    await windowCubit.close();
  }
}

Future<_NativeInkHarness> _pumpHarness(WidgetTester tester) async {
  final fileSystem = MockButterflyFileSystem();
  final settingsCubit = fileSystem.settingsCubit as MockSettingsCubit;
  when(
    () => settingsCubit.state,
  ).thenReturn(const ButterflySettings(autosave: false));
  when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
  final transformCubit = TransformCubit(1);
  final currentIndexCubit = CurrentIndexCubit(
    settingsCubit,
    transformCubit,
    const CameraViewport.unbaked(),
  );
  final windowCubit = WindowCubit(fullScreen: false);
  final page = DocumentPage(layers: [DocumentLayer(id: 'layer')]);
  final (data, pageName) = NoteData(Archive()).setPage(page, 'Page 1');
  final bloc = DocumentBloc(
    fileSystem,
    currentIndexCubit,
    windowCubit,
    data,
    const AssetLocation(path: 'test-note.bfly'),
    null,
    page,
    pageName,
  );
  await currentIndexCubit.changeTool(
    bloc,
    handler: PenHandler(PenTool(id: 'pen')),
    allowBake: false,
  );
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<DocumentBloc>.value(value: bloc),
        BlocProvider<TransformCubit>.value(value: transformCubit),
        BlocProvider<CurrentIndexCubit>.value(value: currentIndexCubit),
        BlocProvider<SettingsCubit>.value(value: settingsCubit),
      ],
      child: const MaterialApp(
        home: NativeInkViewport(child: ColoredBox(color: Colors.white)),
      ),
    ),
  );
  await tester.pump();
  return _NativeInkHarness(
    bloc,
    currentIndexCubit,
    transformCubit,
    windowCubit,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    EinkDisplay.enabled = true;
  });

  tearDown(() {
    EinkDisplay.enabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeInkSession.channel, null);
  });

  testWidgets('failed prepare waits for pen up before retrying', (
    tester,
  ) async {
    if (!NativeInkSession.experiment) return;
    final calls = <MethodCall>[];
    var prepareCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeInkSession.channel, (call) async {
          calls.add(call);
          if (call.method == 'prepare') return ++prepareCalls > 1;
          return true;
        });
    final harness = await _pumpHarness(tester);
    addTearDown(harness.close);

    expect(calls.where((call) => call.method == 'prepare'), hasLength(1));
    final pen = await tester.startGesture(
      const Offset(100, 100),
      kind: PointerDeviceKind.stylus,
      buttons: kPrimaryButton,
    );
    harness.transformCubit.move(const Offset(10, 0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(
      calls.where((call) => call.method == 'prepare'),
      hasLength(1),
      reason: 'A failed prepare must not retry while the pen is down',
    );

    await pen.up();
    await tester.pump();
    await tester.pump();
    expect(calls.where((call) => call.method == 'prepare'), hasLength(2));
    expect(NativeInkSession.instance.active, isTrue);
  });

  testWidgets('stale prepare failure cannot invalidate a newer configuration', (
    tester,
  ) async {
    if (!NativeInkSession.experiment) return;
    final calls = <MethodCall>[];
    final first = Completer<bool>();
    final second = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeInkSession.channel, (call) async {
          calls.add(call);
          if (call.method != 'prepare') return true;
          return calls.where((item) => item.method == 'prepare').length == 1
              ? first.future
              : second.future;
        });
    final harness = await _pumpHarness(tester);
    addTearDown(harness.close);
    expect(calls.where((call) => call.method == 'prepare'), hasLength(1));

    harness.transformCubit.move(const Offset(10, 0));
    await tester.pump();
    await tester.pump();
    expect(calls.where((call) => call.method == 'prepare'), hasLength(2));
    second.complete(true);
    await tester.pump();
    expect(NativeInkSession.instance.active, isTrue);

    first.complete(false);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(calls.where((call) => call.method == 'prepare'), hasLength(2));
    expect(NativeInkSession.instance.active, isTrue);
  });

  testWidgets('successful prepare clears a pending presentation retry', (
    tester,
  ) async {
    if (!NativeInkSession.experiment) return;
    final calls = <MethodCall>[];
    final ready = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeInkSession.channel, (call) async {
          calls.add(call);
          if (call.method == 'prepare') return ready.future;
          return true;
        });
    final harness = await _pumpHarness(tester);
    addTearDown(harness.close);
    expect(calls.where((call) => call.method == 'prepare'), hasLength(1));

    harness.bloc.add(
      ElementsCreated([
        PenElement(
          id: 'committed-while-preparing',
          points: const [PathPoint(10, 10), PathPoint(20, 20)],
        ),
      ]),
    );
    await tester.pump();
    await tester.pump();
    expect(
      (harness.bloc.state as DocumentLoadSuccess).page.content,
      hasLength(1),
    );

    ready.complete(true);
    await tester.pump();
    expect(NativeInkSession.instance.active, isTrue);
    final pen = await tester.startGesture(
      const Offset(100, 100),
      kind: PointerDeviceKind.stylus,
      buttons: kPrimaryButton,
    );
    await pen.up();
    await tester.pump();
    await tester.pump();

    expect(
      calls.where((call) => call.method == 'prepare'),
      hasLength(1),
      reason: 'A successful current prepare must cancel the false retry flag',
    );
    await tester.pump(const Duration(milliseconds: 60));
  });
}
