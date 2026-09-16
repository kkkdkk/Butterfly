import 'package:archive/archive.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/current_index.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/helpers/native_ink.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:material_leap/material_leap.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

class _MockEventContext extends Mock implements EventContext {}

class _CommitTrackingPenHandler extends PenHandler {
  late CurrentIndexCubit currentIndexCubit;
  int commitCalls = 0;
  int viewportUpdateCalls = 0;
  final commitResults = <bool>[];
  final insertedBeforeCommit = <bool>[];

  _CommitTrackingPenHandler() : super(PenTool(id: 'pen'));

  @override
  bool onRenderersCreated(DocumentPage page, List<Renderer> renderers) {
    commitCalls++;
    insertedBeforeCommit.add(
      renderers.every(currentIndexCubit.renderers.contains),
    );
    final result = super.onRenderersCreated(page, renderers);
    commitResults.add(result);
    return result;
  }

  @override
  Future<void> onViewportUpdated(
    CameraViewport currentViewport,
    CameraViewport newViewport,
  ) async {
    viewportUpdateCalls++;
    await super.onViewportUpdated(currentViewport, newViewport);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in ['normal', 'commit-only']) {
    testWidgets('$mode ElementsCreated commits a submitted pen exactly once', (
      tester,
    ) async {
      if (mode == 'commit-only' && !NativeInkSession.diagnosticsEnabled) return;
      final nativeCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeInkSession.channel, (call) async {
            nativeCalls.add(call);
            if (mode == 'commit-only' && call.method == 'prepare') {
              return {'ready': true, 'diagnosticMode': mode};
            }
            return true;
          });
      expect(
        await NativeInkSession.instance.prepare(
          const Rect.fromLTWH(0, 0, 800, 600),
          1,
          captureFrame: (_) async => Uint8List.fromList([137, 80, 78, 71]),
        ),
        isTrue,
      );
      addTearDown(() {
        NativeInkSession.instance.active = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeInkSession.channel, null);
      });

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
      addTearDown(() async {
        await bloc.close();
        await currentIndexCubit.close();
        await windowCubit.close();
      });

      final handler = _CommitTrackingPenHandler()
        ..currentIndexCubit = currentIndexCubit;
      await currentIndexCubit.changeTool(
        bloc,
        handler: handler,
        allowBake: false,
      );
      final stroke = PenElement(
        id: 'native-stroke',
        points: [PathPoint(10, 20, 0.2), PathPoint(40, 20, 0.8)],
      );
      handler.elements[1] = stroke;

      final submission = handler.submitElements(bloc, [1]);
      expect(handler.hasPendingInk, isTrue);
      await submission;

      await tester.pumpAndSettle();

      expect(handler.commitCalls, 1);
      expect(handler.commitResults, [isTrue]);
      expect(handler.insertedBeforeCommit, [isTrue]);
      expect(handler.viewportUpdateCalls, 1);
      expect(handler.hasPendingInk, isFalse);
      final savedStroke = (bloc.state as DocumentLoadSuccess).page.content
          .whereType<PenElement>()
          .single;
      expect(savedStroke.points.map((point) => point.pressure), [0.2, 0.8]);
      if (NativeInkSession.experiment) {
        expect(nativeCalls.where((call) => call.method == 'present'), isEmpty);
      }

      expect(bloc.canUndo, isTrue);
      bloc.undo();
      expect(
        (bloc.state as DocumentLoadSuccess).page.content,
        isEmpty,
        reason: 'One submitted stroke must be one undo step',
      );
    });
  }

  testWidgets(
    'cancel clears only its live pointer and preserves a submitted stroke',
    (tester) async {
      final nativeCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeInkSession.channel, (call) async {
            nativeCalls.add(call);
            return NativeInkSession.diagnosticsEnabled && call.method == 'prepare'
                ? {'ready': true, 'diagnosticMode': 'handoff'}
                : true;
          });
      expect(
        await NativeInkSession.instance.prepare(
          const Rect.fromLTWH(0, 0, 800, 600),
          1,
          captureFrame: (_) async => Uint8List.fromList([137, 80, 78, 71]),
        ),
        isTrue,
      );
      addTearDown(() {
        NativeInkSession.instance.active = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeInkSession.channel, null);
      });

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
      addTearDown(() async {
        await bloc.close();
        await currentIndexCubit.close();
        await windowCubit.close();
      });

      final handler = _CommitTrackingPenHandler()
        ..currentIndexCubit = currentIndexCubit;
      await currentIndexCubit.changeTool(
        bloc,
        handler: handler,
        allowBake: false,
      );
      handler.elements[1] = PenElement(
        id: 'cancelled-stroke',
        points: [PathPoint(10, 10), PathPoint(20, 10)],
      );
      handler.elements[2] = PenElement(
        id: 'submitted-stroke',
        points: [PathPoint(30, 20, 0.2), PathPoint(60, 20, 0.8)],
      );
      handler.elements[3] = PenElement(
        id: 'other-live-stroke',
        points: [PathPoint(70, 30), PathPoint(80, 30)],
      );
      final eventContext = _MockEventContext();
      when(() => eventContext.refreshForegrounds()).thenAnswer((_) async {});

      final submission = handler.submitElements(bloc, [2]);
      await handler.onPointerCancel(
        const PointerCancelEvent(pointer: 1),
        eventContext,
      );
      expect(handler.elements.keys, [3]);
      expect(handler.hasPendingInk, isTrue);

      await handler.onPointerCancel(
        const PointerCancelEvent(pointer: 3),
        eventContext,
      );
      expect(handler.elements, isEmpty);
      expect(
        handler.hasPendingInk,
        isTrue,
        reason: 'Cancelling live pointers must not discard submitted ink',
      );

      await submission;
      await tester.pumpAndSettle();

      expect(handler.hasPendingInk, isFalse);
      expect(handler.commitCalls, 1);
      expect(
        (bloc.state as DocumentLoadSuccess).page.content
            .whereType<PenElement>()
            .map((element) => element.id),
        ['submitted-stroke'],
      );
      expect(
        nativeCalls.where((call) => call.method == 'present'),
        hasLength(NativeInkSession.diagnosticsEnabled ? 1 : 0),
      );
    },
  );
}
