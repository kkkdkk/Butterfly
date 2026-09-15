import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Experimental display-only bridge. Flutter remains the document input source.
class NativeInkSession {
  static const experiment = bool.fromEnvironment('magicpieNativeInk');
  static final instance = NativeInkSession();
  static const channel = MethodChannel('linwood.dev/butterfly/native_ink');

  bool active = false;
  int _generation = 0;
  bool _presentQueued = false;
  Rect? _dirty;
  Size _viewportSize = Size.zero;
  double _dpr = 1;

  void addDirty(Rect canvasRect) {
    if (!active || !canvasRect.isFinite) return;
    final clipped = canvasRect.intersect(Offset.zero & _viewportSize);
    if (clipped.isEmpty) return;
    _dirty = _dirty?.expandToInclude(clipped) ?? clipped;
  }

  Future<bool> _invoke(String method, [Map<String, double>? args]) async {
    try {
      return await channel.invokeMethod<bool>(method, args) ?? false;
    } catch (error) {
      debugPrint('MagicpieInk $method fallback: ${error.runtimeType}');
      return false;
    }
  }

  Future<bool> prepare(Rect rect, double dpr) async {
    final generation = ++_generation;
    active = false;
    _dirty = null;
    _viewportSize = rect.size;
    _dpr = dpr;
    if (rect.isEmpty || !rect.isFinite || !dpr.isFinite || dpr <= 0) {
      await _invoke('dispose');
      return false;
    }
    final ready = await _invoke('prepare', {
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
      'dpr': dpr,
    });
    if (generation != _generation) return false;
    active = ready;
    debugPrint('MagicpieInk prepared=$ready');
    return ready;
  }

  Future<void> dispose() async {
    ++_generation;
    active = false;
    _dirty = null;
    await _invoke('dispose');
  }

  /// Called only once final renderers exist, never from native pen callbacks.
  Future<void> presentAfterFrame({bool Function()? isReady}) async {
    if (!active || _presentQueued || _dirty == null) return;
    final generation = _generation;
    _presentQueued = true;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!active || generation != _generation || !(isReady?.call() ?? true)) {
        return;
      }
      final dirty = _dirty;
      if (dirty == null) return;
      _dirty = null;
      final presented = await _invoke('present', {
        'left': dirty.left * _dpr,
        'top': dirty.top * _dpr,
        'width': dirty.width * _dpr,
        'height': dirty.height * _dpr,
      });
      if (generation == _generation && !presented) active = false;
    } finally {
      _presentQueued = false;
      if (active && _dirty != null && (isReady?.call() ?? true)) {
        unawaited(presentAfterFrame(isReady: isReady));
      }
    }
  }
}
