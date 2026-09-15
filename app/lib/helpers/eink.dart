import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Display-only adaptation: never rewrite document colors.
class EinkDisplay {
  static bool enabled = false;
  static const _inkZone = #magicpieInk;

  static Future<void> initialize({Future<bool?> Function()? detect}) async {
    enabled = false;
    if (detect == null &&
        (kIsWeb || defaultTargetPlatform != TargetPlatform.android)) {
      return;
    }
    try {
      enabled =
          await (detect?.call() ??
              const MethodChannel(
                'linwood.dev/butterfly',
              ).invokeMethod<bool>('isMagicPie')) ??
          false;
    } catch (_) {
      enabled = false;
    }
  }

  static void paint(bool display, VoidCallback callback) => runZoned(
        callback,
        zoneValues: {_inkZone: enabled && display ? _EinkPaintContext() : null},
      );

  static _EinkPaintContext? get _context =>
      Zone.current[_inkZone] as _EinkPaintContext?;

  static bool get isPainting => _context != null;

  static Color get paperColor =>
      _context?.darkPaper == true ? Colors.black : Colors.white;

  /// Sets the document paper contrast before foreground or cache rendering.
  static void preparePaper(Color color) {
    final context = _context;
    if (context != null) context.darkPaper = color.computeLuminance() < 0.5;
  }

  static Color ink(Color original) {
    final context = _context;
    if (context == null || original.a == 0) return original;
    // Preserve white erasing strokes and the opacity of translucent markers.
    final white = original.r > .98 && original.g > .98 && original.b > .98;
    return (white || context.darkPaper ? Colors.white : Colors.black)
        .withValues(alpha: original.a);
  }

  /// Display paper uses a pure light/dark tone so foreground remains legible.
  /// Imported bitmap/PDF/SVG assets do not use this mapping.
  static Color paper(Color original) {
    final context = _context;
    if (context == null || original.a == 0) return original;
    return (context.darkPaper ? Colors.black : Colors.white)
        .withValues(alpha: original.a);
  }
}

class _EinkPaintContext {
  bool darkPaper = false;
}
