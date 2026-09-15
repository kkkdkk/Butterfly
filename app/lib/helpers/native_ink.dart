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
    await _invoke('dispose');
  }

  /// Called only once final renderers exist, never from native pen callbacks.
  Future<void> presentAfterFrame({bool Function()? isReady}) async {
    if (!active || _presentQueued) return;
    final generation = _generation;
    _presentQueued = true;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!active || generation != _generation || !(isReady?.call() ?? true)) {
        return;
      }
      final presented = await _invoke('present');
      if (generation == _generation && !presented) active = false;
    } finally {
      _presentQueued = false;
    }
  }
}
