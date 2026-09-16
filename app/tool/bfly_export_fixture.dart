// From app/: dart run tool/bfly_export_fixture.dart <fixture.bfly> [empty.bfly] [--cjk]
// All content is synthetic. Neither output is allowed to replace an existing file.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:butterfly_api/butterfly_text.dart' as text;
import 'package:dart_leap/dart_leap.dart';
import 'package:image/image.dart' as img;

NoteData _newNote(String name) => NoteData(Archive())
    .setMetadata(
      FileMetadata(
        type: NoteFileType.document,
        fileVersion: kFileVersion,
        name: name,
        description: 'Synthetic CLI export test data; contains no user notes.',
      ),
    )
    .setInfo(DocumentInfo(tools: [SelectTool(), PenTool(), HandTool()]));

TextElement _label(String value, double x, double y, {double size = 22}) =>
    TextElement(
      position: Point(x, y),
      constraint: const ElementConstraint(size: 680, includeArea: false),
      area: text.TextArea(
        paragraph: text.TextParagraph(
          property: text.DefinedParagraphProperty(
            span: text.DefinedSpanProperty(size: size),
          ),
          textSpans: [text.TextSpan(text: value)],
        ),
      ),
    );

PenElement _pressureStroke(double y, {required bool increasing}) => PenElement(
  zoom: 1,
  property: const PenProperty(
    strokeWidth: 24,
    thinning: 0.9,
    smoothing: 0.5,
    streamline: 0.1,
  ),
  // Vary pressure throughout: constant samples activate simulated pressure.
  points: List.generate(81, (index) {
    final progress = index / 80;
    final pressure = increasing ? 0.1 + 0.9 * progress : 1 - 0.9 * progress;
    return PathPoint(60 + 600 * progress, y, pressure);
  }),
);

NoteData _fixture({bool cjk = false}) {
  final bitmap = img.Image(width: 120, height: 120);
  for (var y = 0; y < bitmap.height; y++) {
    for (var x = 0; x < bitmap.width; x++) {
      final black = (x ~/ 20 + y ~/ 20).isEven;
      bitmap.setPixelRgb(
        x,
        y,
        black ? 0 : 255,
        black ? 0 : 255,
        black ? 0 : 255,
      );
    }
  }
  var note = _newNote('BFly PNG export acceptance').setAsset(
    'images/checkerboard.png',
    Uint8List.fromList(img.encodePng(bitmap)),
  );
  note = note
      .setPage(
        DocumentPage(
          backgrounds: [Background.texture(texture: const PatternTexture())],
          areas: [
            const Area(
              name: 'Acceptance board',
              position: Point(0, 0),
              width: 760,
              height: 620,
              isInitial: true,
            ),
          ],
          layers: [
            DocumentLayer(
              content: [
                _label(
                  cjk
                      ? '中文导出测试：压感、笔记、流程图'
                      : 'BFLY EXPORT: TEXT / PRESSURE / IMAGE',
                  40,
                  30,
                ),
                _label('Thin to thick (pressure 0.1 to 1.0)', 40, 95, size: 18),
                _pressureStroke(155, increasing: true),
                _label(
                  'Thick to thin (pressure 1.0 to 0.1)',
                  40,
                  210,
                  size: 18,
                ),
                _pressureStroke(270, increasing: false),
                ImageElement(
                  source: 'images/checkerboard.png',
                  width: 120,
                  height: 120,
                  position: const Point(40, 340),
                ),
                _label('Embedded PNG: 6 x 6 checkerboard', 190, 370, size: 18),
                ShapeElement(
                  firstPosition: const Point(40, 510),
                  secondPosition: const Point(160, 570),
                  property: const ShapeProperty(
                    strokeWidth: 3,
                    shape: RectangleShape(),
                  ),
                ),
                _label('Vector rectangle', 190, 530, size: 18),
              ],
            ),
          ],
        ),
        'Pressure and assets',
      )
      .$1;
  return note
      .setPage(
        DocumentPage(
          backgrounds: [Background.texture(texture: const PatternTexture())],
          areas: [
            const Area(
              name: 'Negative coordinates',
              position: Point(-400, -300),
              width: 800,
              height: 420,
            ),
          ],
          layers: [
            DocumentLayer(
              content: [
                _label('PAGE 2: NEGATIVE COORDINATES', -360, -260),
                ShapeElement(
                  firstPosition: const Point(-350, -180),
                  secondPosition: const Point(-180, -30),
                  property: const ShapeProperty(
                    strokeWidth: 4,
                    shape: CircleShape(fillColor: SRGBColor(0xFFE0E0E0)),
                  ),
                ),
                _label(
                  'This circle must not be clipped.',
                  -150,
                  -130,
                  size: 18,
                ),
                // Outside the named area, this forces bounds export to handle
                // a wide canvas without allocating an unbounded bitmap.
                ShapeElement(
                  firstPosition: const Point(20000, -200),
                  secondPosition: const Point(20200, 0),
                  property: const ShapeProperty(
                    strokeWidth: 5,
                    shape: RectangleShape(fillColor: SRGBColor.black),
                  ),
                ),
              ],
            ),
          ],
        ),
        'Negative and distant',
      )
      .$1;
}

void _writeAndCheck(File output, NoteData note, {required bool empty}) {
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(note.exportAsBytes());
  final loaded = NoteData.fromData(output.readAsBytesSync());
  final pages = loaded.getPages().map((name) => loaded.getPage(name)!).toList();
  final elements = pages.expand((page) => page.content).toList();
  final strokes = elements.whereType<PenElement>().toList();
  if (pages.length != (empty ? 1 : 2) ||
      (empty && elements.isNotEmpty) ||
      (!empty &&
          (elements.length != 13 ||
              strokes.length != 2 ||
              strokes.any((stroke) => stroke.points.length != 81) ||
              strokes.any(
                (stroke) =>
                    stroke.points
                        .map((point) => point.pressure)
                        .toSet()
                        .length <
                    2,
              ) ||
              loaded.getAsset('images/checkerboard.png') == null ||
              pages.any((page) => page.areas.length != 1)))) {
    throw StateError('Fixture round-trip check failed: ${output.path}');
  }
  stdout.writeln(
    'Created ${output.absolute.path} (${output.lengthSync()} bytes; '
    '${pages.length} pages, ${elements.length} elements, ${strokes.length} pressure strokes)',
  );
}

void main(List<String> args) {
  final cjk = args.contains('--cjk');
  args = args.where((argument) => argument != '--cjk').toList();
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/bfly_export_fixture.dart <fixture.bfly> [empty.bfly] [--cjk]',
    );
    exitCode = 64;
    return;
  }
  final outputs = args
      .map((path) => File.fromUri(File(path).absolute.uri.normalizePath()))
      .toList();
  // Check all destinations before writing either document.
  if (outputs.map((file) => file.absolute.path.toLowerCase()).toSet().length !=
      outputs.length) {
    throw ArgumentError('Fixture and empty document must use different paths');
  }
  for (final output in outputs) {
    if (output.existsSync()) {
      throw StateError('Refusing to overwrite ${output.path}');
    }
  }
  _writeAndCheck(outputs.first, _fixture(cjk: cjk), empty: false);
  if (outputs.length == 2) {
    final empty = _newNote(
      'Empty export acceptance',
    ).setPage(const DocumentPage(), 'Empty').$1;
    _writeAndCheck(outputs.last, empty, empty: true);
  }
}
