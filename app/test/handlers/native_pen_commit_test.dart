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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:material_leap/material_leap.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

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

  testWidgets(
    'native-active ElementsCreated commits a submitted pen exactly once',
    (tester) async {
      final nativeCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeInkSession.channel, (call) async {
            nativeCalls.add(call);
            return true;
          });
      expect(
        await NativeInkSession.instance.prepare(
          const Rect.fromLTWH(0, 0, 800, 600),
          1,
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
        expect(
          nativeCalls.where((call) => call.method == 'present'),
          hasLength(1),
        );
      }

      expect(bloc.canUndo, isTrue);
      bloc.undo();
      expect(
        (bloc.state as DocumentLoadSuccess).page.content,
        isEmpty,
        reason: 'One submitted stroke must be one undo step',
      );
    },
  );
}
