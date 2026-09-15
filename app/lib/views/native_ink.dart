import 'dart:async';

import 'package:butterfly/bloc/document_bloc.dart';
import 'package:butterfly/cubits/current_index.dart';
import 'package:butterfly/cubits/settings.dart';
import 'package:butterfly/cubits/transform.dart';
import 'package:butterfly/handlers/handler.dart';
import 'package:butterfly/helpers/eink.dart';
import 'package:butterfly/helpers/native_ink.dart';
import 'package:butterfly_api/butterfly_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_leap/material_leap.dart';

/// An opt-in experiment around the existing canvas; it consumes no input.
class NativeInkViewport extends StatefulWidget {
  final Widget child;

  const NativeInkViewport({super.key, required this.child});

  @override
  State<NativeInkViewport> createState() => _NativeInkViewportState();
}

class _NativeInkViewportState extends State<NativeInkViewport>
    with WidgetsBindingObserver {
  final _boundsKey = GlobalKey();
  final _session = NativeInkSession.instance;
  Object? _configuration;
  Object? _viewport;
  bool _resumed = true;
  bool _updateQueued = false;
  int _down = 0, _move = 0, _up = 0, _cancel = 0;
  double _pressureMin = double.infinity, _pressureMax = 0;

  bool get _enabled => NativeInkSession.experiment && EinkDisplay.enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_enabled) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_globalPointer);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_enabled) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_globalPointer);
    }
    if (_enabled) unawaited(_session.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _configuration = null;
    if (!_enabled) return;
    unawaited(_session.dispose());
    if (_resumed) setState(() {});
  }

  void _scheduleUpdate() {
    if (_updateQueued) return;
    _updateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateQueued = false;
      if (mounted) _update();
    });
  }

  void _update() {
    final document = context.read<DocumentBloc>().state;
    final cubit = context.read<CurrentIndexCubit>();
    final index = cubit.state;
    final handler = cubit.getHandler();
    final transform = context.read<TransformCubit>().state;
    final settings = context.read<SettingsCubit>().state;
    final bounds = _boundsKey.currentContext?.findRenderObject();
    // First experiment is deliberately restricted to plain black pen on light
    // paper. Do not substitute the native path for rulers or mapped tools.
    final safe =
        _resumed &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        document is DocumentLoadSuccess &&
        !document.absolute &&
        document.currentArea == null &&
        document.page.backgrounds.every(
          (background) =>
              background is TextureBackground &&
              background.defaultColor.toColor().computeLuminance() > 0.9,
        ) &&
        handler is PenHandler &&
        !handler.data.shapeDetectionEnabled &&
        handler.data.property.color == const SRGBColor(0xFF000000) &&
        index.toggleableHandlers.isEmpty &&
        index.temporaryHandler == null &&
        index.pointers.length <= 1 &&
        settings.inputConfiguration.pen.getCategory() ==
            InputMappingCategory.activeTool &&
        settings.inputConfiguration.holdShortcuts.isEmpty &&
        !settings.hasFlag(kMultiTapInputShortcutsFlag) &&
        transform.friction == null &&
        bounds is RenderBox &&
        bounds.hasSize;
    if (!safe) {
      if (_configuration != null || _session.active) {
        _configuration = null;
        unawaited(_session.dispose());
      }
      return;
    }
    final rect = bounds.localToGlobal(Offset.zero) & bounds.size;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final configuration = (
      rect,
      dpr,
      document.pageName,
      transform,
      handler.data,
    );
    if (configuration != _configuration) {
      _configuration = configuration;
      _viewport = index.cameraViewport;
      unawaited(_session.prepare(rect, dpr));
    } else if (_viewport != index.cameraViewport) {
      _viewport = index.cameraViewport;
      unawaited(
        _session.presentAfterFrame(isReady: () => !handler.hasPendingInk),
      );
    }
  }

  void _audit(PointerEvent event) {
    if (event.kind != PointerDeviceKind.stylus) {
      return;
    }
    if (event is PointerDownEvent) {
      _down++;
      _pressureMin = double.infinity;
      _pressureMax = 0;
    }
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      final pressure = getPressureOfEvent(event);
      if (pressure < _pressureMin) _pressureMin = pressure;
      if (pressure > _pressureMax) _pressureMax = pressure;
    }
    if (event is PointerMoveEvent) _move++;
    if (event is PointerUpEvent) _up++;
    if (event is PointerCancelEvent) _cancel++;
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      debugPrint(
        'MagicpieInk Flutter down=$_down move=$_move up=$_up '
        'cancel=$_cancel native=${_session.active} '
        'pressure=$_pressureMin..$_pressureMax',
      );
      if (event is PointerCancelEvent) {
        _configuration = null;
        unawaited(_session.dispose());
      }
    }
  }

  void _globalPointer(PointerEvent event) {
    // Toolbar touches are outside the canvas Listener, but must suspend native
    // ink too. Re-evaluate tool/route/bounds after the gesture finishes.
    final bounds = _boundsKey.currentContext?.findRenderObject();
    final inCanvas =
        bounds is RenderBox &&
        bounds.hasSize &&
        (bounds.localToGlobal(Offset.zero) & bounds.size).contains(
          event.position,
        );
    final ordinaryPen =
        event.kind == PointerDeviceKind.stylus &&
        (event.buttons & ~kPrimaryButton) == 0 &&
        inCanvas;
    if (event is PointerCancelEvent ||
        (event is PointerDownEvent && !ordinaryPen)) {
      _configuration = null;
      unawaited(_session.dispose());
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_configuration == null && mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    context.watch<DocumentBloc>();
    context.watch<CurrentIndexCubit>();
    context.watch<TransformCubit>();
    context.watch<SettingsCubit>();
    ModalRoute.isCurrentOf(context);
    _scheduleUpdate();
    return Listener(
      key: _boundsKey,
      onPointerDown: _audit,
      onPointerMove: _audit,
      onPointerUp: _audit,
      onPointerCancel: _audit,
      child: widget.child,
    );
  }
}
