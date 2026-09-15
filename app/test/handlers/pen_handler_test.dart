import 'package:archive/archive.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/current_index.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final handler = PenHandler(PenTool(id: 'pen'));

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
  });
}
