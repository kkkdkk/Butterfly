import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/helpers/eink.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly/view_painter.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/material.dart' show ColorScheme, CustomPainter;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_leap/material_leap.dart';

Future<ui.Image> _solidImage(ui.Color color, {int size = 1}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size, size);
  } finally {
    picture.dispose();
  }
}

Future<ui.Color> _renderCenter(
  Renderer renderer, {
  required bool display,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  EinkDisplay.paint(
    display,
    () => renderer.build(
      canvas,
      const ui.Size(10, 10),
      NoteData(Archive()),
      const DocumentPage(),
      const DocumentInfo(),
      const CameraTransform(),
    ),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(10, 10);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (5 * 10 + 5) * 4;
    return ui.Color.fromARGB(
      bytes!.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<ui.Color> _paintCenter(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), const ui.Size(10, 10));
  final picture = recorder.endRecording();
  final image = await picture.toImage(10, 10);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (5 * 10 + 5) * 4;
    return ui.Color.fromARGB(
      bytes!.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => EinkDisplay.enabled = false);

  test(
    'shape raster is monochrome on display and original color off display',
    () async {
      EinkDisplay.enabled = true;
      final renderer = ShapeRenderer(
        ShapeElement(
          firstPosition: const Point(0, 0),
          secondPosition: const Point(10, 10),
          property: const ShapeProperty(
            strokeWidth: 0,
            shape: RectangleShape(fillColor: SRGBColor(0xFFFF0000)),
          ),
        ),
      );

      expect(
        await _renderCenter(renderer, display: true),
        const ui.Color(0xFF000000),
      );
      expect(
        await _renderCenter(renderer, display: false),
        const ui.Color(0xFFFF0000),
      );
    },
  );

  test('pen raster uses the same display-only color policy', () async {
    EinkDisplay.enabled = true;
    final renderer = PenRenderer(
      PenElement(
        points: const [PathPoint(1, 5), PathPoint(5, 5), PathPoint(9, 5)],
        property: const PenProperty(
          color: SRGBColor(0xFFFF0000),
          strokeWidth: 6,
          thinning: 0,
        ),
      ),
    );

    expect(
      await _renderCenter(renderer, display: true),
      const ui.Color(0xFF000000),
    );
    expect(
      await _renderCenter(renderer, display: false),
      const ui.Color(0xFFFF0000),
    );
  });

  test(
    'dark paper contrast applies when cache paint omits background',
    () async {
      EinkDisplay.enabled = true;
      final element = ShapeElement(
        firstPosition: const Point(0, 0),
        secondPosition: const Point(10, 10),
        property: const ShapeProperty(
          strokeWidth: 0,
          shape: RectangleShape(fillColor: SRGBColor.black),
        ),
      );
      final renderer = ShapeRenderer(element);
      final page = DocumentPage(
        backgrounds: [
          Background.texture(
            texture: const PatternTexture(boxColor: SRGBColor.black),
          ),
        ],
      );
      final painter = ViewPainter(
        NoteData(Archive()),
        page,
        const DocumentInfo(),
        einkDisplay: true,
        renderBackground: false,
        cameraViewport: CameraViewport.unbaked(unbakedElements: [renderer]),
      );

      expect(await _paintCenter(painter), const ui.Color(0xFFFFFFFF));
    },
  );

  test('dark paper contrast applies to foreground preview', () async {
    EinkDisplay.enabled = true;
    final renderer = ShapeRenderer(
      ShapeElement(
        firstPosition: const Point(0, 0),
        secondPosition: const Point(10, 10),
        property: const ShapeProperty(
          strokeWidth: 0,
          shape: RectangleShape(fillColor: SRGBColor.black),
        ),
      ),
    );
    final page = DocumentPage(
      backgrounds: [
        Background.texture(
          texture: const PatternTexture(boxColor: SRGBColor.black),
        ),
      ],
    );
    final painter = ForegroundPainter(
      [renderer],
      NoteData(Archive()),
      page,
      const DocumentInfo(),
      const ColorScheme.light(),
    );

    expect(await _paintCenter(painter), const ui.Color(0xFFFFFFFF));
  });

  test('imported image pixels are not mapped by display ink scope', () async {
    EinkDisplay.enabled = true;
    final source = await _solidImage(const ui.Color(0xFFFF0000), size: 10);
    final renderer = ImageRenderer(
      ImageElement(source: 'images/source.png', width: 10, height: 10),
      null,
      source,
    );

    expect(
      await _renderCenter(renderer, display: true),
      const ui.Color(0xFFFF0000),
    );
    renderer.dispose();
  });

  test('export viewport drops monochrome main and layer caches', () async {
    final cache = await _solidImage(const ui.Color(0xFF000000));
    final below = await _solidImage(const ui.Color(0xFF000000));
    final above = await _solidImage(const ui.Color(0xFF000000));
    final bottomElement = ShapeElement(
      firstPosition: const Point(0, 0),
      secondPosition: const Point(10, 10),
    );
    final topElement = ShapeElement(
      firstPosition: const Point(0, 0),
      secondPosition: const Point(10, 10),
    );
    final bottomRenderer = ShapeRenderer(bottomElement, 'bottom');
    final topRenderer = ShapeRenderer(topElement, 'top');
    final page = DocumentPage(
      layers: [
        DocumentLayer(id: 'bottom', content: [bottomElement]),
        DocumentLayer(id: 'top', content: [topElement]),
      ],
    );
    final viewport = CameraViewport.baked(
      image: cache,
      belowLayerImage: below,
      aboveLayerImage: above,
      width: 10,
      height: 10,
      pixelRatio: 1,
      resolution: RenderResolution.performance,
      bakedElements: [bottomRenderer],
      unbakedElements: [topRenderer],
      visibleElements: [bottomRenderer, topRenderer],
      visibleUnbakedElements: [topRenderer],
    );

    final export = viewport.forExport(page);
    expect(export.image, isNull);
    expect(export.belowLayerImage, isNull);
    expect(export.aboveLayerImage, isNull);
    expect(export.unbakedElements, [bottomRenderer, topRenderer]);
    expect(export.visibleUnbakedElements, [bottomRenderer, topRenderer]);

    viewport.disposeImages();
  });

  test('.bfly round trip preserves colors and imported asset bytes', () {
    const color = SRGBColor(0x807A21E8);
    const fill = SRGBColor(0x40F5C400);
    const assetPath = 'images/imported.png';
    final asset = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    final page = DocumentPage(
      layers: [
        DocumentLayer(
          id: 'layer',
          content: [
            PenElement(
              points: const [PathPoint(1, 1), PathPoint(8, 8)],
              property: const PenProperty(color: color, fill: fill),
            ),
          ],
        ),
      ],
    );
    var data = NoteData(Archive()).setAsset(assetPath, asset);
    final result = data.setPage(page, 'Page');
    data = result.$1;

    final loaded = NoteData.fromData(data.exportAsBytes());
    final loadedPen = loaded.getPage(result.$2)!.content.single as PenElement;
    expect(loadedPen.property.color, color);
    expect(loadedPen.property.fill, fill);
    expect(loaded.getAsset(assetPath), asset);
  });
}
