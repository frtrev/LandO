import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/property.dart';
import '../services/geometry_service.dart';
import '../services/property_repository.dart';

class PropertyController extends ChangeNotifier {
  final PropertyRepository repository;
  final GeometryService geometry;
  Property? property;
  GeometryResult result = const GeometryResult();
  bool dirty = false;
  bool saving = false;
  int _revision = 0;
  String? storageError;
  Timer? _draftTimer;
  Future<void> _writes = Future.value();
  Future<void> persistDraft() {
    _draftTimer?.cancel();
    final data = dirty && property != null
        ? jsonEncode(property!.toJson())
        : '';
    _writes = _writes.then((_) async {
      await repository.setPreference('draft', data);
      storageError = null;
    });
    return _writes = _writes.catchError((Object error) {
      storageError = 'Could not preserve recovery draft: $error';
    });
  }

  Future<void> discardDraft() async {
    _draftTimer?.cancel();
    await _writes;
    await repository.setPreference('draft', '');
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    super.dispose();
  }

  String? activeLayerId;
  PropertyLayer? get activeLayer =>
      property?.layers.where((layer) => layer.id == activeLayerId).firstOrNull;
  final Map<String, GeometryResult> areaResults = {};
  final Map<String, double> pathLengths = {};
  final Map<String, List<String>> layerErrors = {};
  bool get canSave =>
      property != null &&
      result.valid &&
      layerErrors.values.every((errors) => errors.isEmpty);
  void _calculateLayers() {
    areaResults.clear();
    pathLengths.clear();
    layerErrors.clear();
    for (final layer in property?.layers ?? <PropertyLayer>[]) {
      if (layer.kind == LayerKind.area) {
        final r = geometry.calculate(layer.points);
        areaResults[layer.id] = r;
        layerErrors[layer.id] = r.errors;
      } else {
        final errors = <String>[];
        if (layer.points.length < 2) {
          errors.add('Add at least two points to this measurement.');
        }
        try {
          if (layer.points.any((p) => !geometry.validCoordinate(p))) {
            errors.add('Invalid path coordinates.');
          }
          if (errors.isEmpty) {
            for (var i = 1; i < layer.points.length; i++) {
              if (geometry.distance(layer.points[i - 1], layer.points[i]) <
                  .001) {
                errors.add('Consecutive path points must be different.');
                break;
              }
            }
          }
          if (errors.isEmpty) {
            pathLengths[layer.id] = geometry.pathLength(layer.points);
          }
        } on Object {
          errors.add('This path cannot be calculated. Check its coordinates.');
        }
        layerErrors[layer.id] = errors;
      }
    }
  }

  PropertyController(this.repository, {GeometryService? geometry})
    : geometry = geometry ?? GeometryService();
  Future<void> reloadAfterRestore() async {
    _draftTimer?.cancel();
    await _writes;
    property = null;
    dirty = false;
    activeLayerId = null;
    storageError = null;
    await restore();
    _calculate();
  }

  Future<void> restore() async {
    final draft = await repository.preference('draft');
    if (draft != null && draft.isNotEmpty) {
      property = Property.fromJson(jsonDecode(draft) as Map<String, dynamic>);
      dirty = true;
      _calculate();
      return;
    }
    final id = await repository.preference('lastProperty');
    final saved = await repository.list();
    for (final p in saved) {
      if (p.id == id) {
        await open(p);
        break;
      }
    }
  }

  Future<void> open(Property p) async {
    await discardDraft();
    await repository.setPreference('lastProperty', p.id);
    property = p;
    dirty = false;
    activeLayerId = null;
    _calculate();
  }

  void create(
    String name,
    List<BoundaryPoint> points,
    double lat,
    double lon,
    double zoom,
  ) {
    final now = DateTime.now().toUtc();
    property = Property(
      id: newId(),
      name: name,
      points: points,
      latitude: lat,
      longitude: lon,
      zoom: zoom,
      created: now,
      modified: now,
    );
    activeLayerId = null;
    changed();
  }

  void changed() {
    _revision++;
    dirty = true;
    _calculate();
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 300), persistDraft);
  }

  void _calculate() {
    result = property == null
        ? const GeometryResult()
        : geometry.calculate(property!.points);
    _calculateLayers();
    notifyListeners();
  }

  void move(String id, double lat, double lon) {
    final p = property!;
    p.points = p.points.map((v) => v.id == id ? v.move(lat, lon) : v).toList();
    changed();
  }

  void insertAfter(int index) {
    final p = property!;
    p.points.insert(
      index + 1,
      geometry.midpoint(
        p.points[index],
        p.points[(index + 1) % p.points.length],
        label: pointLabel(p.nextLabel++),
      ),
    );
    changed();
  }

  void remove(String id) {
    if (property!.points.length <= 3) {
      return;
    }
    property!.points.removeWhere((p) => p.id == id);
    changed();
  }

  Future<void> save() async {
    if (property == null || !canSave || saving) {
      return;
    }
    saving = true;
    notifyListeners();
    try {
      property!.modified = DateTime.now().toUtc();
      final revision = _revision;
      final snapshot = Property.fromJson(property!.toJson());
      await repository.save(snapshot);
      if (_revision == revision && property?.id == snapshot.id) {
        await discardDraft();
        dirty = false;
      } else {
        await persistDraft();
      }
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  PropertyLayer startLayer(LayerKind kind, String name) {
    if (property == null) {
      throw StateError('Open a property first.');
    }
    final layer = PropertyLayer(id: newId(), kind: kind, name: name.trim());
    property!.layers.add(layer);
    activeLayerId = layer.id;
    changed();
    return layer;
  }

  bool replaceAreaPoints(String id, List<BoundaryPoint> points) {
    final layer = property!.layers.firstWhere((layer) => layer.id == id);
    if (layer.kind != LayerKind.area ||
        !layer.visible ||
        !geometry.calculate(points).valid) {
      return false;
    }
    layer.points = List.of(points);
    changed();
    return true;
  }

  void cycleLayerTagUnit(String id) {
    final layer = property!.layers.firstWhere((layer) => layer.id == id);
    layer.cycleTagUnit(metric: property!.metric);
    changed();
  }

  void toggleLayerVisibility(String id) {
    final layer = property!.layers.firstWhere((layer) => layer.id == id);
    layer.visible = !layer.visible;
    if (!layer.visible && activeLayerId == id) activeLayerId = null;
    changed();
  }

  void selectLayer(String id) {
    final layer = property!.layers.firstWhere((layer) => layer.id == id);
    activeLayerId = id;
    if (!layer.visible) {
      layer.visible = true;
      changed();
    } else {
      notifyListeners();
    }
  }

  void finishLayer() {
    activeLayerId = null;
    notifyListeners();
  }

  void renameLayer(String id, String name) {
    if (name.trim().isEmpty) {
      return;
    }
    property!.layers.firstWhere((layer) => layer.id == id).name = name.trim();
    changed();
  }

  void deleteLayer(String id) {
    property!.layers.removeWhere((layer) => layer.id == id);
    if (activeLayerId == id) {
      activeLayerId = null;
    }
    changed();
  }

  void addLayerPoint(double lat, double lon) {
    final layer = activeLayer;
    if (layer == null) {
      return;
    }
    layer.points.add(
      BoundaryPoint(
        id: newId(),
        label: pointLabel(layer.nextLabel++),
        latitude: lat,
        longitude: lon,
      ),
    );
    changed();
  }

  void moveLayerPoint(String layerId, String pointId, double lat, double lon) {
    final layer = property!.layers.firstWhere((layer) => layer.id == layerId);
    layer.points = layer.points
        .map((p) => p.id == pointId ? p.move(lat, lon) : p)
        .toList();
    changed();
  }

  void removeLayerPoint(String layerId, String pointId) {
    property!.layers
        .firstWhere((layer) => layer.id == layerId)
        .points
        .removeWhere((p) => p.id == pointId);
    changed();
  }

  void insertLayerPoint(String layerId, int index) {
    final layer = property!.layers.firstWhere((layer) => layer.id == layerId);
    if (layer.points.length < 2 ||
        (layer.kind == LayerKind.distance &&
            index == layer.points.length - 1)) {
      return;
    }
    layer.points.insert(
      index + 1,
      geometry.midpoint(
        layer.points[index],
        layer.points[(index + 1) % layer.points.length],
        label: pointLabel(layer.nextLabel++),
      ),
    );
    changed();
  }

  void clearLayer() {
    activeLayer?.points.clear();
    changed();
  }

  void undoLayerPoint() {
    final layer = activeLayer;
    if (layer != null && layer.points.isNotEmpty) {
      layer.points.removeLast();
      changed();
    }
  }

  void close() {
    property = null;
    dirty = false;
    activeLayerId = null;
    _calculate();
  }
}
