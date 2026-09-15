import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Display-only adaptation: never rewrite document colors.
class EinkDisplay {
  static bool enabled = false;
  static const _inkZone = #magicpieInk;

  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      enabled = await const MethodChannel('linwood.dev/butterfly')
              .invokeMethod<bool>('isMagicPie') ??
          false;
    } on MissingPluginException {
      enabled = false;
    }
  }

  static void paint(bool display, VoidCallback callback) =>
      runZoned(callback, zoneValues: {_inkZone: enabled && display});

  static Color ink(Color original) {
    if (Zone.current[_inkZone] != true || original.a == 0) return original;
    // Preserve white erasing strokes and the opacity of translucent markers.
    final white = original.r > .98 && original.g > .98 && original.b > .98;
    return (white ? Colors.white : Colors.black).withValues(alpha: original.a);
  }
}
