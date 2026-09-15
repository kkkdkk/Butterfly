// From app/: dart run tool/magicpie_fixture.dart ../.magicpie-output/fixture.bfly
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:dart_leap/dart_leap.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final output = File(args.single);
  if (output.existsSync()) throw StateError('Refusing to overwrite $output');
  PenElement stroke(double y, int color) => PenElement(
    points: [PathPoint(80, y), PathPoint(200, y), PathPoint(320, y)],
    property: PenProperty(
      color: SRGBColor(color),
      strokeWidth: 12,
      thinning: 0,
    ),
  );
  var note = NoteData(Archive())
      .setMetadata(
        const FileMetadata(
          type: NoteFileType.document,
          fileVersion: kFileVersion,
          name: 'Magic Pie color compatibility fixture',
          description: 'Synthetic test data; contains no user notes.',
        ),
      )
      .setInfo(
        DocumentInfo(
          tools: [
            SelectTool(),
            PenTool(),
            PathEraserTool(),
            UndoTool(),
            RedoTool(),
            HandTool(),
          ],
        ),
      );
  final redImage = img.fill(
    img.Image(width: 64, height: 64),
    color: img.ColorRgb8(255, 0, 0),
  );
  note = note.setAsset(
    'images/red.png',
    Uint8List.fromList(img.encodePng(redImage)),
  );
  note = note
      .setPage(
        DocumentPage(
          backgrounds: [Background.texture(texture: const PatternTexture())],
          layers: [
            DocumentLayer(
              content: [
                stroke(100, 0xFFFF0000),
                stroke(160, 0xFF0000FF),
                stroke(220, 0x80008000),
                ShapeElement(
                  firstPosition: const Point(80, 280),
                  secondPosition: const Point(320, 420),
                  property: const ShapeProperty(
                    shape: RectangleShape(fillColor: SRGBColor(0xFF00FFFF)),
                  ),
                ),
                ImageElement(
                  source: 'images/red.png',
                  width: 120,
                  height: 120,
                  position: const Point(380, 80),
                ),
              ],
            ),
          ],
        ),
        'Light paper',
      )
      .$1;
  note = note
      .setPage(
        DocumentPage(
          backgrounds: [
            Background.texture(
              texture: const PatternTexture(boxColor: SRGBColor.black),
            ),
          ],
          layers: [
            DocumentLayer(
              content: [stroke(100, 0xFFFFFFFF), stroke(160, 0xFF0000FF)],
            ),
          ],
        ),
        'Dark paper',
      )
      .$1;
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(note.exportAsBytes());
  final loaded = NoteData.fromData(output.readAsBytesSync());
  if (loaded.getPages().length != 2 ||
      loaded.getAsset('images/red.png') == null) {
    throw StateError('Fixture round-trip failed');
  }
  stdout.writeln(
    'Created ${output.absolute.path} (${output.lengthSync()} bytes)',
  );
}
