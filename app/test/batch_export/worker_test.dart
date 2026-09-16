import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:butterfly/batch_export/worker.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

NoteData _document(List<DocumentPage> pages) {
  var document = NoteData(Archive()).setMetadata(
    const FileMetadata(type: NoteFileType.document, fileVersion: kFileVersion),
  );
  for (var i = 0; i < pages.length; i++) {
    document = document.setPage(pages[i], 'Page $i').$1;
  }
  return document;
}

Future<BatchExportWorker> _worker(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  late BuildContext context;
  await tester.pumpWidget(
    Builder(
      builder: (value) {
        context = value;
        return const SizedBox();
      },
    ),
  );
  return BatchExportWorker(context, SettingsCubit(prefs));
}

Map<String, Object> _load(NoteData document) => {
  'op': 'load',
  'base64': base64Encode(document.exportAsBytes()),
};

void main() {
  testWidgets('lists pages and duplicate-named areas without modifying input', (
    tester,
  ) async {
    final worker = await _worker(tester);
    final document = _document([
      const DocumentPage(
        areas: [
          Area(name: 'same', width: 100, height: 200, position: Point(0, 0)),
          Area(name: 'same', width: 300, height: 400, position: Point(-50, 10)),
        ],
      ),
      const DocumentPage(),
    ]);
    final before = document.exportAsBytes();
    final result = await worker.request(_load(document));
    expect(result['protocolVersion'], 1);
    final pages = result['pages'] as List;
    expect(pages.length, 2);
    expect(pages.first['displayName'], 'Page 0');
    expect(pages.first['pageIndex'], 0);
    expect(pages.first['areas'][1]['areaIndex'], 1);
    expect(document.exportAsBytes(), before);
    await expectLater(
      worker.request({
        'op': 'render',
        'pageName': pages.first['name'],
        'areaName': 'same',
      }),
      throwsFormatException,
    );
    await worker.request({'op': 'dispose'});
  });

  testWidgets('a rejected request does not poison the serial queue', (
    tester,
  ) async {
    final worker = await _worker(tester);
    await expectLater(worker.request({'op': 'unknown'}), throwsFormatException);
    await expectLater(worker.request({'op': 'render'}), throwsStateError);
    final result = await worker.request(
      _load(_document([const DocumentPage()])),
    );
    expect((result['pages'] as List).length, 1);
    await worker.request({'op': 'dispose'});
    await expectLater(worker.request({'op': 'load'}), throwsStateError);
  });

  testWidgets('external and missing embedded assets fail before rendering', (
    tester,
  ) async {
    final worker = await _worker(tester);
    for (final source in ['https://example.com/private.png', 'missing.png']) {
      final document = _document([
        DocumentPage(
          layers: [
            DocumentLayer(
              content: [
                ImageElement(
                  source: source,
                  position: const Point(0, 0),
                  width: 100,
                  height: 100,
                ),
              ],
            ),
          ],
        ),
      ]);
      final result = await worker.request(_load(document));
      await expectLater(
        worker.request({
          'op': 'render',
          'pageName': (result['pages'] as List).first['name'],
        }),
        throwsFormatException,
      );
    }
    await worker.request({'op': 'dispose'});
  });

  testWidgets(
    'embedded PDFs fail with an actionable unsupported-format error',
    (tester) async {
      final worker = await _worker(tester);
      final document = _document([
        DocumentPage(
          layers: [
            DocumentLayer(
              content: [
                PdfElement(source: 'embedded.pdf', width: 100, height: 100),
              ],
            ),
          ],
        ),
      ]);
      final loaded = await worker.request(_load(document));
      await expectLater(
        worker.request({
          'op': 'render',
          'pageName': (loaded['pages'] as List).first['name'],
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Convert the PDF pages to images in Butterfly'),
          ),
        ),
      );
      await worker.request({'op': 'dispose'});
    },
  );

  testWidgets('an empty page produces bounded PNG bytes', (tester) async {
    final worker = await _worker(tester);
    await tester.runAsync(() async {
      final result = await worker.request(
        _load(_document([const DocumentPage()])),
      );
      final png = await worker.request({
        'op': 'render',
        'pageName': (result['pages'] as List).first['name'],
        'maxDimension': 128,
      });
      expect(png['width'], 128);
      expect(png['height'], 96);
      expect(png['actualScale'], 0.125);
      expect(png['limited'], isTrue);
      expect(base64Decode(png['base64'] as String).take(8), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
      await worker.request({'op': 'dispose'});
    });
  });
}
