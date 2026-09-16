import 'dart:math';

import 'package:archive/archive.dart';
import 'package:butterfly/api/file_system.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/current_index.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lw_file_system/lw_file_system.dart';
import 'package:material_leap/material_leap.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

Future<void> _settleBlocEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<List<String?>> _storedElementIds(DocumentFileSystem fileSystem) async {
  final stored = await fileSystem.getAsset('test-note.bfly');
  final page = (stored as FileSystemFile<NoteFile>).data!.load()!.getPage(
    'Page 1',
  );
  return page!.content.map((element) => element.id).toList();
}

Future<void> _waitForStoredElementIds(
  DocumentFileSystem fileSystem,
  List<String?> expected,
) async {
  for (var i = 0; i < 100; i++) {
    final actual = await _storedElementIds(fileSystem);
    if (const ListEquality<String?>().equals(actual, expected)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(await _storedElementIds(fileSystem), expected);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(AssetLocation.empty));

  late MockButterflyFileSystem fileSystem;
  late MockSettingsCubit settingsCubit;
  late CurrentIndexCubit currentIndexCubit;
  late WindowCubit windowCubit;
  late DocumentBloc bloc;
  late DocumentFileSystem documentFileSystem;

  setUp(() async {
    fileSystem = MockButterflyFileSystem();
    settingsCubit = fileSystem.settingsCubit as MockSettingsCubit;
    when(
      () => settingsCubit.state,
    ).thenReturn(const ButterflySettings(autosave: false));
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => settingsCubit.getRemote(any())).thenReturn(null);
    when(() => settingsCubit.addRecentHistory(any())).thenAnswer((_) async {});

    currentIndexCubit = CurrentIndexCubit(
      settingsCubit,
      TransformCubit(1),
      const CameraViewport.unbaked(),
    );
    windowCubit = WindowCubit(fullScreen: false);

    const page = DocumentPage(layers: [DocumentLayer(id: 'layer')]);
    final (data, pageName) = NoteData(Archive()).setPage(page, 'Page 1');
    const location = AssetLocation(path: 'test-note.bfly');
    documentFileSystem = fileSystem.buildDocumentSystem();
    await documentFileSystem.updateFile(location.path, data.toFile());
    bloc = DocumentBloc(
      fileSystem,
      currentIndexCubit,
      windowCubit,
      data,
      location,
      null,
      page,
      pageName,
    );
  });

  tearDown(() async {
    if (!bloc.isClosed) await bloc.close();
    if (!currentIndexCubit.isClosed) await currentIndexCubit.close();
    if (!windowCubit.isClosed) await windowCubit.close();
  });

  test('undo and redo transitions mark the document unsaved', () async {
    bloc.add(
      ElementsCreated([
        ShapeElement(
          id: 'shape',
          firstPosition: const Point(10, 10),
          secondPosition: const Point(20, 20),
        ),
      ]),
    );
    await _settleBlocEvents();
    currentIndexCubit.setSaveState(saved: SaveState.saved);

    bloc.sendUndo();
    final afterUndo = currentIndexCubit.state.saved;
    currentIndexCubit.setSaveState(saved: SaveState.saved);
    bloc.sendRedo();
    final afterRedo = currentIndexCubit.state.saved;

    expect(
      [afterUndo, afterRedo],
      everyElement(SaveState.unsaved),
      reason: 'Replay history changes the document and must enable Save.',
    );
  });

  test(
    'force save persists current data even when save state is saved',
    () async {
      bloc.add(
        ElementsCreated([
          ShapeElement(
            id: 'shape',
            firstPosition: const Point(10, 10),
            secondPosition: const Point(20, 20),
          ),
        ]),
      );
      await _settleBlocEvents();
      currentIndexCubit.setSaveState(saved: SaveState.saved);

      await bloc.save(force: true);

      final stored = await documentFileSystem.getAsset('test-note.bfly');
      final storedPage = (stored as FileSystemFile<NoteFile>).data!
          .load()!
          .getPage('Page 1');
      expect(
        storedPage!.content.map((element) => element.id),
        ['shape'],
        reason:
            'Explicit Save must not return early just because state is saved.',
      );
    },
  );

  test('undo and redo results can each be saved roundtrip', () async {
    bloc.add(
      ElementsCreated([
        ShapeElement(
          id: 'shape',
          firstPosition: const Point(10, 10),
          secondPosition: const Point(20, 20),
        ),
      ]),
    );
    await _settleBlocEvents();
    await bloc.save(force: true);

    bloc.sendUndo();
    await bloc.save(force: true);
    var stored = await documentFileSystem.getAsset('test-note.bfly');
    var storedPage = (stored as FileSystemFile<NoteFile>).data!.load()!.getPage(
      'Page 1',
    );
    expect(storedPage!.content, isEmpty);

    bloc.sendRedo();
    await bloc.save(force: true);
    stored = await documentFileSystem.getAsset('test-note.bfly');
    storedPage = (stored as FileSystemFile<NoteFile>).data!.load()!.getPage(
      'Page 1',
    );
    expect(storedPage!.content.map((element) => element.id), ['shape']);
  });

  test('force save does not bypass absolute read-only state', () async {
    bloc.add(
      ElementsCreated([
        ShapeElement(
          id: 'shape',
          firstPosition: const Point(10, 10),
          secondPosition: const Point(20, 20),
        ),
      ]),
    );
    await _settleBlocEvents();
    currentIndexCubit.setSaveState(absolute: true);

    await bloc.save(force: true);
    expect(await _storedElementIds(documentFileSystem), isEmpty);

    bloc.sendUndo();
    expect(currentIndexCubit.state.saved, SaveState.absoluteRead);
  });

  test('undo triggers autosave after marking the document unsaved', () async {
    bloc.add(
      ElementsCreated([
        ShapeElement(
          id: 'shape',
          firstPosition: const Point(10, 10),
          secondPosition: const Point(20, 20),
        ),
      ]),
    );
    await _settleBlocEvents();
    await bloc.save(force: true);
    expect(await _storedElementIds(documentFileSystem), ['shape']);
    when(() => settingsCubit.state).thenReturn(
      const ButterflySettings(
        autosave: true,
        delayedAutosave: true,
        autosaveDelaySeconds: 0,
      ),
    );
    expect(
      (bloc.state as DocumentLoadSuccess).hasAutosave(
        currentIndexCubit.state.networkingService,
        currentIndexCubit.state.embedding,
      ),
      isTrue,
    );

    bloc.sendUndo();
    expect(currentIndexCubit.state.saved, SaveState.unsaved);
    await _waitForStoredElementIds(documentFileSystem, []);
    expect(currentIndexCubit.state.saved, SaveState.saved);
  });
}
