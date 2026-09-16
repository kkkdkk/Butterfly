import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Experimental display-only bridge. Flutter remains the document input source.
typedef NativeInkFrameCapture = Future<Uint8List?> Function(double dpr);

enum NativeInkDiagnosticMode { normal, recordOnly, commitOnly, handoff }

class NativeInkSession {
  static const experiment = bool.fromEnvironment('magicpieNativeInk');
  static const diagnosticsEnabled =
      experiment && bool.fromEnvironment('magicpieNativeInkDiagnostics');
  static final instance = NativeInkSession();
  static const channel = MethodChannel('linwood.dev/butterfly/native_ink');

  bool active = false;
  NativeInkDiagnosticMode diagnosticMode = NativeInkDiagnosticMode.normal;
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
    diagnosticMode = NativeInkDiagnosticMode.normal;
    _dirty = null;
    _dirtyRevision++;
    _viewportSize = rect.size;
    _dpr = dpr;
    _captureFrame = captureFrame;
    if (rect.isEmpty || !rect.isFinite || !dpr.isFinite || dpr <= 0) {
      await _invoke('dispose');
      return false;
    }
    Object? response;
    try {
      response = await channel.invokeMethod<Object?>('prepare', {
        'left': rect.left,
        'top': rect.top,
        'width': rect.width,
        'height': rect.height,
        'dpr': dpr,
        if (diagnosticsEnabled) 'diagnosticEnabled': true,
      });
    } catch (error) {
      debugPrint('MagicpieInk prepare fallback: ${error.runtimeType}');
    }
    if (generation != _generation) return false;
    final ready =
        response == true ||
        (diagnosticsEnabled && response is Map && response['ready'] == true);
    if (diagnosticsEnabled && response is Map) {
      diagnosticMode = switch (response['diagnosticMode']) {
        'record-only' => NativeInkDiagnosticMode.recordOnly,
        'commit-only' => NativeInkDiagnosticMode.commitOnly,
        'handoff' => NativeInkDiagnosticMode.handoff,
        _ => NativeInkDiagnosticMode.normal,
      };
      debugPrint('MagicpieInk diagnosticMode=${diagnosticMode.name}');
    }
    active = ready;
    debugPrint('MagicpieInk prepared=$ready');
    return ready;
  }

  Future<void> dispose() async {
    ++_generation;
    active = false;
    diagnosticMode = NativeInkDiagnosticMode.normal;
    _dirty = null;
    _dirtyRevision++;
    _captureFrame = null;
    await _invoke('dispose');
  }

  /// Called only once final renderers exist, never from native pen callbacks.
  Future<void> presentAfterFrame({bool Function()? isReady}) async {
    if (!active || _presentQueued || _dirty == null) return;
    // Keep the native session continuous. Per-stroke capture/restart reproduced
    // disappearing ink on hardware; retain it only for explicit diagnostics.
    if (diagnosticMode != NativeInkDiagnosticMode.handoff) {
      debugPrint(
        'MagicpieInk diagnostic skip capture/present: ${diagnosticMode.name}',
      );
      _dirty = null;
      return;
    }
    final generation = _generation;
    final timing = diagnosticsEnabled ? (Stopwatch()..start()) : null;
    _presentQueued = true;
    var recapture = false;
    try {
      final binding = WidgetsBinding.instance;
      if (binding.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
        binding.scheduleFrame();
      }
      await binding.endOfFrame;
      if (timing != null) {
        debugPrint(
          'MagicpieInk handoff endOfFrameMs=${timing.elapsedMilliseconds}',
        );
      }
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
        if (timing != null) {
          debugPrint(
            'MagicpieInk handoff captureReadyMs=${timing.elapsedMilliseconds} bytes=${image?.length}',
          );
        }
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
      if (timing != null) {
        debugPrint(
          'MagicpieInk handoff completedMs=${timing.elapsedMilliseconds} presented=$presented',
        );
      }
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
