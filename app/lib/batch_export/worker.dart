import 'dart:convert';

import 'package:butterfly/api/file_system.dart';
import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/current_index.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/helpers/element.dart';
import 'package:butterfly/models/viewport.dart';
import 'package:butterfly/renderers/renderer.dart';
import 'package:butterfly/services/asset.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_leap/material_leap.dart';

import 'geometry.dart';

/// Read-only renderer; no document bloc, storage methods, or sync are started.
class BatchExportWorker {
  final SettingsCubit settings;
  final ButterflyFileSystem fileSystem;
  final WindowCubit window = WindowCubit(fullScreen: false);
  NoteData? _document;
  Future<void> _queue = Future.value();
  bool _disposed = false;
  bool _hasExtraFont = false;

  BatchExportWorker(BuildContext context, this.settings)
    : fileSystem = ButterflyFileSystem(context, settings);

  Future<Map<String, Object?>> request(Map<String, dynamic> request) {
    final result = _queue.then((_) => _execute(request));
    // A failed request does not poison the serial queue.
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Map<String, Object?>> _execute(Map<String, dynamic> request) async {
    if (_disposed) throw StateError('Export worker has been disposed');
    switch (request['op']) {
      case 'loadFont':
        if (_document != null) {
          throw StateError('Load fonts before loading a document');
        }
        final encoded = request['base64'];
        if (encoded is! String ||
            encoded.isEmpty ||
            request['family'] != 'Roboto') {
          throw const FormatException(
            'loadFont requires base64 bytes and family Roboto',
          );
        }
        final loader = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(base64Decode(encoded))));
        await loader.load();
        _hasExtraFont = true;
        return {'fontLoaded': true, 'family': 'Roboto'};
      case 'load':
        _document = null;
        final encoded = request['base64'];
        if (encoded is! String || encoded.isEmpty) {
          throw const FormatException('load requires base64 document bytes');
        }
        final document = NoteData.fromData(base64Decode(encoded));
        if (!document.isValid || document.getPages(true).isEmpty) {
          throw const FormatException(
            'Not a valid Butterfly document with pages',
          );
        }
        final pages = <Map<String, Object?>>[];
        for (final (displayName, name) in document.getPagesWithNames()) {
          final page = document.getPage(name);
          if (page == null) throw FormatException('Cannot decode page: $name');
          pages.add({
            'name': name,
            'displayName': displayName,
            'pageIndex': pages.length,
            'areas': [
              for (var i = 0; i < page.areas.length; i++)
                {
                  'name': page.areas[i].name,
                  'areaIndex': i,
                  'bounds': exportRectJson(_areaRect(page.areas[i])),
                },
            ],
          });
        }
        _document = document;
        return {'protocolVersion': 1, 'pages': pages};
      case 'render':
        return _render(request);
      case 'dispose':
        _document = null;
        _disposed = true;
        fileSystem.dispose();
        await window.close();
        await settings.close();
        return {'disposed': true};
      default:
        throw const FormatException('Unknown export operation');
    }
  }

  Future<Map<String, Object?>> _render(Map<String, dynamic> request) async {
    final document = _document;
    if (document == null) throw StateError('Load a document before rendering');
    final pageName = request['pageName'];
    if (pageName is! String || !document.getPages(true).contains(pageName)) {
      throw const FormatException('Unknown pageName');
    }
    final page = document.getPage(pageName)!;
    final margin = _number(request, 'margin', 24);
    if (margin < 0) throw const FormatException('margin cannot be negative');
    final scale = _number(request, 'scale', 2);
    final maxDimension = _integer(request, 'maxDimension', 4096);
    final maxPixels = _integer(request, 'maxPixels', 16777216);
    final areaIndex = _selectArea(request, page);
    final warnings = <String>[];
    if (!_hasExtraFont &&
        page.content.any(
          (element) =>
              element is LabelElement &&
              RegExp(
                r'[\u2e80-\u9fff\uf900-\ufaff]',
              ).hasMatch(jsonEncode(element.toJson())),
        )) {
      warnings.add(
        'CJK text needs a local font supplied with --font; handwritten paths do not need a font',
      );
    }
    _validateAssets(document, page);

    final transform = TransformCubit(1);
    final index = CurrentIndexCubit(
      settings,
      transform,
      const CameraViewport.unbaked(),
      absolute: true,
    );
    final assets = AssetService();
    final state = DocumentLoadSuccess(
      document,
      page: page,
      fileSystem: fileSystem,
      windowCubit: window,
      pageName: pageName,
      assetService: assets,
      absolute: true,
    );
    final backgrounds = page.backgrounds
        .map((e) => Renderer<Background>.fromInstance(e))
        .toList();
    final renderers = [
      for (final layer in page.layers)
        for (final element in layer.content)
          Renderer<PadElement>.fromInstance(element, layer.id),
    ];
    try {
      for (final renderer in [...backgrounds, ...renderers]) {
        await renderer.setup(transform, document, assets, page);
      }
      // Text/math can change its bounds when made visible. Initialize before
      // calculating the content crop, then update at the final export scale.
      for (final renderer in renderers) {
        if (renderer is GenericTextRenderer) {
          await renderer.onVisible(
            index,
            state,
            const CameraTransform(),
            const Size(1024, 768),
          );
        }
      }
      final bounds = areaIndex == null
          ? exportContentBounds([
              ...renderers.map((renderer) => renderer.expandedRect),
              ...page.backgrounds.map(_backgroundRect),
            ], margin: margin)
          : _areaRect(page.areas[areaIndex]);
      final geometry = ExportGeometry.fit(
        bounds,
        scale: scale,
        maxDimension: maxDimension,
        maxPixels: maxPixels,
      );
      final camera = CameraTransform(geometry.actualScale, bounds.topLeft);
      for (final renderer in renderers) {
        await renderer.onVisible(index, state, camera, bounds.size);
        if (renderer is ImageRenderer && renderer.image == null ||
            renderer is SvgRenderer && renderer.pictureInfo == null) {
          throw StateError('Failed to render an embedded image or SVG');
        }
      }
      for (final renderer in backgrounds) {
        if (renderer is ImageBackgroundRenderer && renderer.image == null) {
          throw StateError('Failed to render an embedded background image');
        }
      }
      final bytes = await index.render(
        document,
        page,
        state.info,
        ImageExportOptions(
          x: bounds.left,
          y: bounds.top,
          width: bounds.width,
          height: bounds.height,
          quality: geometry.actualScale,
        ),
        cameraViewport: CameraViewport.unbaked(
          backgrounds: backgrounds,
          unbakedElements: renderers,
        ),
      );
      if (bytes == null) throw StateError('Renderer did not produce PNG bytes');
      if (geometry.limited) {
        warnings.add('Image was downscaled to fit the configured pixel limits');
      }
      return {
        'pageName': pageName,
        'pageIndex': document.getPages(true).indexOf(pageName),
        'areaName': areaIndex == null ? null : page.areas[areaIndex].name,
        'areaIndex': areaIndex,
        ...geometry.toJson(),
        'mimeType': 'image/png',
        'base64': base64Encode(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        ),
        'warnings': warnings,
      };
    } finally {
      for (final renderer in [...backgrounds, ...renderers]) {
        renderer.dispose();
      }
      try {
        await assets.dispose();
      } finally {
        try {
          await index.close();
        } finally {
          await transform.close();
        }
      }
    }
  }

  static Rect _areaRect(Area area) =>
      Rect.fromLTWH(area.position.x, area.position.y, area.width, area.height);

  static Rect? _backgroundRect(Background background) => switch (background) {
    ImageBackground e => Rect.fromLTWH(
      0,
      0,
      e.width * e.scaleX,
      e.height * e.scaleY,
    ),
    SvgBackground e => Rect.fromLTWH(
      0,
      0,
      e.width * e.scaleX,
      e.height * e.scaleY,
    ),
    _ => null,
  };

  static int? _selectArea(Map<String, dynamic> request, DocumentPage page) {
    final index = request['areaIndex'];
    if (index != null) {
      if (index is! num ||
          !index.isFinite ||
          index != index.toInt() ||
          index < 0 ||
          index >= page.areas.length) {
        throw const FormatException('areaIndex is out of range');
      }
      return index.toInt();
    }
    final name = request['areaName'];
    if (name == null) return null;
    final matches = [
      for (var i = 0; i < page.areas.length; i++)
        if (page.areas[i].name == name) i,
    ];
    if (matches.length != 1) {
      throw const FormatException('areaName must identify exactly one area');
    }
    return matches.single;
  }

  static double _number(
    Map<String, dynamic> request,
    String key,
    double fallback,
  ) {
    final value = request[key] ?? fallback;
    if (value is! num || !value.isFinite) {
      throw FormatException('$key must be a finite number');
    }
    return value.toDouble();
  }

  static int _integer(Map<String, dynamic> request, String key, int fallback) {
    final value = _number(request, key, fallback.toDouble());
    if (value != value.toInt()) {
      throw FormatException('$key must be an integer');
    }
    return value.toInt();
  }

  static void _validateAssets(NoteData document, DocumentPage page) {
    for (final item in [...page.backgrounds, ...page.content]) {
      if (item is PdfElement) {
        throw const FormatException(
          'The standalone exporter does not yet support embedded PDF elements. '
          'Convert the PDF pages to images in Butterfly before exporting.',
        );
      }
      if (item is SourcedElement) {
        final uri = Uri.tryParse(item.source);
        if (uri == null ||
            uri.hasScheme && !uri.isScheme('data') && !uri.isScheme('file')) {
          throw const FormatException('External asset URLs are not allowed');
        }
        if (getDataFromSource(document, item.source) == null) {
          throw const FormatException('An embedded document asset is missing');
        }
      }
      if (item is Background) {
        final rect = _backgroundRect(item);
        if (rect != null && (!isFiniteExportRect(rect) || rect.isEmpty)) {
          throw const FormatException('Background tile dimensions are invalid');
        }
      }
    }
  }
}
