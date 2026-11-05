import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/property.dart';

class _AreaHoldRecognizer extends LongPressGestureRecognizer {
  bool Function(Offset) allowed = (_) => false;
  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      allowed(event.position) && super.isPointerAllowed(event);
}

/// Competes with the native map only for holds inside a visible custom area.
/// Quick pans, zoom gestures and holds outside shapes remain native map input.
class AreaDragSurface extends StatefulWidget {
  final Widget child;
  final List<PropertyLayer> areas;
  final List<BoundaryPoint> excludedPoints;
  final bool enabled;
  final bool hasSelection;
  final VoidCallback? onTapOutside;
  final Future<Offset> Function(LatLng) project;
  final Future<LatLng> Function(Offset) unproject;
  final ValueChanged<String> onStart;
  final void Function(String, LatLng, LatLng) onMove;
  final VoidCallback onEnd, onCancel;
  const AreaDragSurface({
    super.key,
    required this.child,
    required this.areas,
    required this.enabled,
    required this.project,
    required this.unproject,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.onCancel,
    this.hasSelection = false,
    this.onTapOutside,
    this.excludedPoints = const [],
  });
  @override
  State<AreaDragSurface> createState() => AreaDragSurfaceState();
}

class AreaDragSurfaceState extends State<AreaDragSurface> {
  Map<String, Path> _regions = {};
  List<Offset> _excluded = [];
  int _projectionVersion = 0, _session = 0;
  String? _candidate, _dragId;
  Future<LatLng>? _origin;
  Offset? _pending;
  bool _flushing = false, _ending = false;
  String _signature = '';
  ({int pointer, Offset start, Duration time})? _outsideTouch;
  final Set<int> _pointers = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refreshProjection());
  }

  @override
  void didUpdateWidget(covariant AreaDragSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = [
      for (final a in widget.areas)
        '${a.id}:${a.points.map((p) => '${p.latitude},${p.longitude}').join(';')}',
      for (final p in widget.excludedPoints)
        'excluded:${p.latitude},${p.longitude}',
    ].join('|');
    if (signature != _signature || widget.enabled != oldWidget.enabled) {
      _signature = signature;
      if (_dragId == null) {
        _regions = {};
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => refreshProjection(),
        );
      }
    }
  }

  void cameraMoving() {
    _projectionVersion++;
    _regions = {};
  }

  Future<void> refreshProjection() async {
    if (!mounted || !widget.enabled || _dragId != null) return;
    final version = ++_projectionVersion;
    final areas = [
      for (final a in widget.areas)
        (id: a.id, points: List<BoundaryPoint>.of(a.points)),
    ];
    try {
      final regions = <String, Path>{};
      for (final area in areas) {
        final points = await Future.wait(
          area.points.map(
            (p) => widget.project(LatLng(p.latitude, p.longitude)),
          ),
        );
        if (points.length >= 3) {
          regions[area.id] = Path()..addPolygon(points, true);
        }
      }
      final excluded = await Future.wait(
        widget.excludedPoints.map(
          (p) => widget.project(LatLng(p.latitude, p.longitude)),
        ),
      );
      if (mounted && version == _projectionVersion) {
        _regions = regions;
        _excluded = excluded;
      }
    } on Object {
      // A map can be disposed or its projection unavailable while changing views.
      if (version == _projectionVersion) _regions = {};
    }
  }

  void _pointerDown(PointerDownEvent event) {
    _pointers.add(event.pointer);
    _outsideTouch = _pointers.length == 1 && _outsideAllowed(event.position)
        ? (pointer: event.pointer, start: event.position, time: event.timeStamp)
        : null;
  }

  void _pointerMove(PointerMoveEvent event) {
    final touch = _outsideTouch;
    if (touch != null &&
        touch.pointer == event.pointer &&
        (event.position - touch.start).distance > kTouchSlop) {
      _outsideTouch = null;
    }
  }

  void _pointerUp(PointerUpEvent event) {
    final touch = _outsideTouch;
    _outsideTouch = null;
    _pointers.remove(event.pointer);
    if (touch != null &&
        touch.pointer == event.pointer &&
        event.timeStamp - touch.time < kLongPressTimeout &&
        (event.position - touch.start).distance <= kTouchSlop &&
        widget.enabled &&
        widget.hasSelection) {
      widget.onTapOutside?.call();
    }
  }

  bool _outsideAllowed(Offset global) {
    if (!widget.enabled ||
        !widget.hasSelection ||
        _dragId != null ||
        _regions.isEmpty) {
      return false;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final local = box.globalToLocal(global);
    return !_regions.values.any((region) => region.contains(local));
  }

  bool _allowed(Offset global) {
    if (!widget.enabled || _dragId != null) return false;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final local = box.globalToLocal(global);
    if (_excluded.any((p) => (p - local).distance < 24)) return false;
    for (final entry in _regions.entries.toList().reversed) {
      if (entry.value.contains(local)) {
        _candidate = entry.key;
        return true;
      }
    }
    _candidate = null;
    return false;
  }

  void _start(LongPressStartDetails details) {
    final id = _candidate;
    if (id == null || !widget.enabled) return;
    final session = ++_session;
    _dragId = id;
    _ending = false;
    _origin = widget.unproject(details.localPosition);
    _origin!.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (mounted && session == _session && _dragId == id) _cancel();
      },
    );
    widget.onStart(id);
    HapticFeedback.selectionClick();
  }

  void _move(Offset point, {bool ending = false}) {
    if (_dragId == null) return;
    _pending = point;
    _ending = ending;
    _flush();
  }

  Future<void> _flush() async {
    if (_flushing || _dragId == null) return;
    _flushing = true;
    final session = _session;
    try {
      final origin = await _origin!;
      while (mounted && session == _session && _pending != null) {
        final point = _pending!;
        _pending = null;
        final position = await widget.unproject(point);
        if (mounted && session == _session && _dragId != null) {
          widget.onMove(_dragId!, origin, position);
        }
      }
      if (mounted && session == _session && _ending) {
        _dragId = null;
        _origin = null;
        _ending = false;
        widget.onEnd();
        refreshProjection();
      }
    } on Object {
      if (mounted && session == _session) _cancel();
    } finally {
      _flushing = false;
      if (mounted && _pending != null && _dragId != null) _flush();
    }
  }

  void _cancel() {
    if (_dragId == null) return;
    _session++;
    _dragId = null;
    _pending = null;
    _origin = null;
    _ending = false;
    widget.onCancel();
    refreshProjection();
  }

  @override
  void dispose() {
    _session++;
    _dragId = null;
    _pending = null;
    _origin = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _pointerDown,
    onPointerMove: _pointerMove,
    onPointerUp: _pointerUp,
    onPointerCancel: (event) {
      _pointers.remove(event.pointer);
      _outsideTouch = null;
      _cancel();
    },
    child: RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _AreaHoldRecognizer:
            GestureRecognizerFactoryWithHandlers<_AreaHoldRecognizer>(
              _AreaHoldRecognizer.new,
              (recognizer) {
                recognizer.allowed = _allowed;
                recognizer.onLongPressStart = _start;
                recognizer.onLongPressMoveUpdate = (details) {
                  _move(details.localPosition);
                };
                recognizer.onLongPressEnd = (details) {
                  _move(details.localPosition, ending: true);
                };
                recognizer.onLongPressCancel = _cancel;
              },
            ),
      },
      child: widget.child,
    ),
  );
}
