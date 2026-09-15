import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/helpers/eink.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly/services/asset.dart';
import 'package:butterfly/view_painter.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:butterfly_api/butterfly_text.dart' as text;
import 'package:flutter/material.dart'
    show ColorScheme, CustomPainter, TextSpan;
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

Future<List<ui.Color>> _renderColors(
  Renderer renderer, {
  required bool display,
  ui.Color? paper,
  ui.Size size = const ui.Size(100, 40),
}) async {
  final recorder = ui.PictureRecorder();
  EinkDisplay.paint(display, () {
    if (paper != null) EinkDisplay.preparePaper(paper);
    renderer.build(
      ui.Canvas(recorder),
      size,
      NoteData(Archive()),
      const DocumentPage(),
      const DocumentInfo(),
      const CameraTransform(),
    );
  });
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return [
      for (var offset = 0; offset < bytes!.lengthInBytes; offset += 4)
        if (bytes.getUint8(offset + 3) > 0)
          ui.Color.fromARGB(
            bytes.getUint8(offset + 3),
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          ),
    ];
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

  for (final overlay in const {
    'transparent': SRGBColor(0x00000000),
    'translucent': SRGBColor(0x40000000),
  }.entries) {
    test(
      '${overlay.key} dark grid overlay keeps underlying white paper',
      () async {
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
              texture: const PatternTexture(boxColor: SRGBColor.white),
            ),
            Background.texture(
              texture: PatternTexture(boxColor: overlay.value),
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

        expect(await _paintCenter(painter), const ui.Color(0xFF000000));
      },
    );
  }

  test(
    'text painter restores original color after monochrome raster',
    () async {
      EinkDisplay.enabled = true;
      final element = TextElement(
        foreground: const SRGBColor(0xFFFF0000),
        area: const text.TextArea(
          paragraph: text.TextParagraph(
            property: text.ParagraphProperty.defined(
              span: text.DefinedSpanProperty(
                size: 24,
                underline: true,
                decorationColor: SRGBColor(0xFF00FF00),
                backgroundColor: SRGBColor(0x800000FF),
              ),
            ),
            textSpans: [text.InlineSpan.text(text: 'M')],
          ),
        ),
      );
      final renderer = TextRenderer(element);
      final transformCubit = TransformCubit(1);
      await renderer.setup(
        transformCubit,
        NoteData(Archive()),
        AssetService(),
        const DocumentPage(),
      );

      final originalSpan = renderer.span as TextSpan;
      expect(originalSpan.style?.backgroundColor, const ui.Color(0x800000FF));
      final display = await _renderColors(renderer, display: true);
      final exported = await _renderColors(renderer, display: false);
      expect(display, isNotEmpty);
      expect(exported, isNotEmpty);
      expect(
        display.every(
          (color) =>
              (color.r - color.g).abs() < .01 &&
              (color.g - color.b).abs() < .01,
        ),
        isTrue,
      );
      expect(exported.any((color) => color.r > .9 && color.g < .1), isTrue);
      expect(identical(renderer.span, originalSpan), isTrue);
      renderer.dispose();
      transformCubit.close();
    },
  );

  test('light inline text background overrides dark page contrast', () async {
    EinkDisplay.enabled = true;
    final renderer = TextRenderer(
      TextElement(
        foreground: const SRGBColor(0xFFFF0000),
        area: const text.TextArea(
          paragraph: text.TextParagraph(
            property: text.ParagraphProperty.defined(
              span: text.DefinedSpanProperty(
                size: 24,
                backgroundColor: SRGBColor.white,
              ),
            ),
            textSpans: [text.InlineSpan.text(text: 'M')],
          ),
        ),
      ),
    );
    final transformCubit = TransformCubit(1);
    await renderer.setup(
      transformCubit,
      NoteData(Archive()),
      AssetService(),
      const DocumentPage(),
    );

    final display = await _renderColors(
      renderer,
      display: true,
      paper: const ui.Color(0xFF000000),
    );
    expect(display.any((color) => color.r < .1 && color.a > .5), isTrue);
    renderer.dispose();
    transformCubit.close();
  });

  test(
    'low-alpha dark inline background keeps black glyph on light paper',
    () async {
      EinkDisplay.enabled = true;
      final renderer = TextRenderer(
        TextElement(
          foreground: const SRGBColor(0xFFFF0000),
          area: const text.TextArea(
            paragraph: text.TextParagraph(
              property: text.ParagraphProperty.defined(
                span: text.DefinedSpanProperty(
                  size: 24,
                  backgroundColor: SRGBColor(0x0D000000),
                ),
              ),
              textSpans: [text.InlineSpan.text(text: 'M')],
            ),
          ),
        ),
      );
      final transformCubit = TransformCubit(1);
      await renderer.setup(
        transformCubit,
        NoteData(Archive()),
        AssetService(),
        const DocumentPage(),
      );

      final display = await _renderColors(renderer, display: true);
      expect(
        display.any(
          (color) =>
              color.a > .5 && color.r < .1 && color.g < .1 && color.b < .1,
        ),
        isTrue,
      );
      renderer.dispose();
      transformCubit.close();
    },
  );

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
      id: 'bottom-element',
      firstPosition: const Point(0, 0),
      secondPosition: const Point(10, 10),
      property: const ShapeProperty(
        strokeWidth: 0,
        shape: RectangleShape(fillColor: SRGBColor(0xFFFF0000)),
      ),
    );
    final topElement = ShapeElement(
      id: 'top-element',
      firstPosition: const Point(0, 0),
      secondPosition: const Point(10, 10),
      property: const ShapeProperty(
        strokeWidth: 0,
        shape: RectangleShape(fillColor: SRGBColor(0xFF0000FF)),
      ),
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
      bakedElements: [topRenderer],
      unbakedElements: [bottomRenderer],
      visibleElements: [bottomRenderer, topRenderer],
      visibleUnbakedElements: [topRenderer],
    );

    final export = viewport.forExport(page);
    expect(export.image, isNull);
    expect(export.belowLayerImage, isNull);
    expect(export.aboveLayerImage, isNull);
    expect(export.unbakedElements, [bottomRenderer, topRenderer]);
    expect(export.visibleUnbakedElements, [bottomRenderer, topRenderer]);
    final exportPainter = ViewPainter(
      NoteData(Archive()),
      page,
      const DocumentInfo(),
      einkDisplay: false,
      renderBackground: false,
      cameraViewport: export,
    );
    expect(await _paintCenter(exportPainter), const ui.Color(0xFF0000FF));

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
