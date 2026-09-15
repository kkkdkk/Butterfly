import 'package:archive/archive.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/current_index.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/helpers/eink.dart';
import 'package:butterfly/helpers/native_ink.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly/renderers/renderer.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('active pen foreground contains points added after the first', (
    tester,
  ) async {
    EinkDisplay.enabled = true;
    final nativeCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeInkSession.channel, (call) async {
          nativeCalls.add(call);
          return true;
        });
    addTearDown(() {
      EinkDisplay.enabled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeInkSession.channel, null);
    });
    final fileSystem = MockButterflyFileSystem();
    final settingsCubit = fileSystem.settingsCubit as MockSettingsCubit;
    when(() => settingsCubit.state).thenReturn(
      const ButterflySettings(
        autosave: false,
        ignorePressure: IgnorePressure.never,
      ),
    );
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
    BuildContext? buildContext;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<DocumentBloc>.value(value: bloc),
          BlocProvider<TransformCubit>.value(value: transformCubit),
          BlocProvider<CurrentIndexCubit>.value(value: currentIndexCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              buildContext = context;
              return const NativeInkViewport(child: SizedBox.expand());
            },
          ),
        ),
      ),
    );
    final handler = PenHandler(PenTool(id: 'pen'));
    await currentIndexCubit.changeTool(
      bloc,
      handler: handler,
      allowBake: false,
    );
    await tester.pumpAndSettle();
    if (NativeInkSession.experiment) {
      expect(
        nativeCalls.where((call) => call.method == 'prepare'),
        isNotEmpty,
        reason: 'Default active-tool pen mapping must allow native preview',
      );
    }

    handler.addPoint(
      buildContext!,
      1,
      const Offset(10, 20),
      const Size(800, 600),
      0.5,
      PointerDeviceKind.stylus,
      refresh: false,
      shouldCreate: true,
    );
    final firstPointElement = handler.elements[1]!;
    handler.addPoint(
      buildContext!,
      1,
      const Offset(40, 20),
      const Size(800, 600),
      0.75,
      PointerDeviceKind.stylus,
      refresh: false,
    );

    expect(handler.elements[1], isNot(same(firstPointElement)));
    final state = bloc.state as DocumentLoadSuccess;
    final foreground = handler
        .createForegrounds(
          currentIndexCubit,
          state.data,
          state.page,
          state.info,
        )
        .whereType<PenRenderer>()
        .single;
    expect(foreground.element.points, const [
      PathPoint(10, 20, 0.5),
      PathPoint(40, 20, 0.75),
    ]);
    expect(foreground.shouldSimulatePressure(), isTrue);
    handler.addPoint(
      buildContext!,
      1,
      const Offset(70, 20),
      const Size(800, 600),
      0.2,
      PointerDeviceKind.stylus,
      refresh: false,
    );
    final pressureElement = handler.elements[1]!;
    expect(PenRenderer(pressureElement).shouldSimulatePressure(), isFalse);
    await handler.submitElements(bloc, [1]);
    await tester.pumpAndSettle();
    final savedState = bloc.state as DocumentLoadSuccess;
    final submitted = savedState.page.content.whereType<PenElement>().single;
    expect(submitted.points.map((p) => p.pressure), [0.5, 0.75, 0.2]);
    final bytes = await tester.runAsync(() => savedState.saveBytes());
    final reopened = NoteData.fromData(bytes!).getPage(pageName)!;
    final restored = reopened.content.whereType<PenElement>().single;
    expect(restored.id, pressureElement.id);
    expect(restored.points, pressureElement.points);
  });

  test('stylus pressure normalization preserves changes in force', () {
    final pressures = [100.0, 2000.0, 4000.0]
        .map(
          (pressure) => getPressureOfEvent(
            PointerMoveEvent(
              kind: PointerDeviceKind.stylus,
              pressure: pressure,
              pressureMin: 0,
              pressureMax: 4095,
            ),
          ),
        )
        .toList();
    expect(pressures[0], closeTo(100 / 4095, 0.00001));
    expect(pressures[1], closeTo(2000 / 4095, 0.00001));
    expect(pressures[2], closeTo(4000 / 4095, 0.00001));
  });
}
