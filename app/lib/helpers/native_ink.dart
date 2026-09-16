import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Experimental display-only bridge. Flutter remains the document input source.
typedef NativeInkFrameCapture = Future<Uint8List?> Function(double dpr);

class NativeInkSession {
  static const experiment = bool.fromEnvironment('magicpieNativeInk');
  static final instance = NativeInkSession();
  static const channel = MethodChannel('linwood.dev/butterfly/native_ink');

  bool active = false;
  int _generation = 0;
  bool _presentQueued = false;
  Rect? _dirty;
  int _dirtyRevision = 0;
  Size _viewportSize = Size.zero;
  double _dpr = 1;
  NativeInkFrameCapture? _captureFrame;

  void addDirty(Rect canvasRect) {
    if (!active || !canvasRect.isFinite) return;
    final clipped = canvasRect.intersect(Offset.zero & _viewportSize);
    if (clipped.isEmpty) return;
    _dirty = _dirty?.expandToInclude(clipped) ?? clipped;
    _dirtyRevision++;
  }

  Future<bool> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      return await channel.invokeMethod<bool>(method, args) ?? false;
    } catch (error) {
      debugPrint('MagicpieInk $method fallback: ${error.runtimeType}');
      return false;
    }
  }

  Future<bool> prepare(
    Rect rect,
    double dpr, {
    NativeInkFrameCapture? captureFrame,
  }) async {
    final generation = ++_generation;
    active = false;
    _dirty = null;
    _dirtyRevision++;
    _viewportSize = rect.size;
    _dpr = dpr;
    _captureFrame = captureFrame;
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
    _dirtyRevision++;
    _captureFrame = null;
    await _invoke('dispose');
  }

  /// Called only once final renderers exist, never from native pen callbacks.
  Future<void> presentAfterFrame({bool Function()? isReady}) async {
    if (!active || _presentQueued || _dirty == null) return;
    final generation = _generation;
    _presentQueued = true;
    var recapture = false;
    try {
      final binding = WidgetsBinding.instance;
      if (binding.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
        binding.scheduleFrame();
      }
      await binding.endOfFrame;
      if (!active || generation != _generation || !(isReady?.call() ?? true)) {
        return;
      }
      final dirty = _dirty;
      final revision = _dirtyRevision;
      final captureFrame = _captureFrame;
      if (dirty == null) return;
      if (captureFrame == null) {
        await dispose();
        return;
      }
      Uint8List? image;
      try {
        image = await captureFrame(_dpr);
      } catch (error) {
        debugPrint('MagicpieInk capture fallback: ${error.runtimeType}');
        if (generation == _generation && active) await dispose();
        return;
      }
      if (!active || generation != _generation || !(isReady?.call() ?? true)) {
        return;
      }
      if (revision != _dirtyRevision) {
        recapture = true;
        return;
      }
      if (image == null || image.isEmpty) {
        await dispose();
        return;
      }
      final presented = await _invoke('present', {
        'left': dirty.left * _dpr,
        'top': dirty.top * _dpr,
        'width': dirty.width * _dpr,
        'height': dirty.height * _dpr,
        'image': image,
      });
      if (generation != _generation) return;
      if (!presented) {
        await dispose();
      } else if (revision == _dirtyRevision) {
        _dirty = null;
      } else {
        recapture = true;
      }
    } finally {
      _presentQueued = false;
      if (recapture && active && _dirty != null && (isReady?.call() ?? true)) {
        unawaited(presentAfterFrame(isReady: isReady));
      }
    }
  }
}
