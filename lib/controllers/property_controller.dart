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
  String? storageError;
  Timer? _draftTimer;
  Future<void> _writes = Future.value();
  Future<void> persistDraft() {
    _draftTimer?.cancel();
    final data = dirty && property != null
        ? jsonEncode(property!.toJson())
        : '';
    _writes = _writes.then((_) => repository.setPreference('draft', data));
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

  final List<BoundaryPoint> measurement = [];
  PropertyController(this.repository, {GeometryService? geometry})
    : geometry = geometry ?? GeometryService();
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
    measurement.clear();
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
    measurement.clear();
    changed();
  }

  void changed() {
    dirty = true;
    _calculate();
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 300), persistDraft);
  }

  void _calculate() {
    result = property == null
        ? const GeometryResult()
        : geometry.calculate(property!.points);
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
    if (property == null || !result.valid || saving) {
      return;
    }
    saving = true;
    notifyListeners();
    try {
      property!.modified = DateTime.now().toUtc();
      await repository.save(property!);
      await discardDraft();
      dirty = false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  void addMeasurement(double lat, double lon) {
    measurement.add(
      BoundaryPoint(
        id: newId(),
        label: '${measurement.length + 1}',
        latitude: lat,
        longitude: lon,
      ),
    );
    notifyListeners();
  }

  void clearMeasurement() {
    measurement.clear();
    notifyListeners();
  }

  void undoMeasurement() {
    if (measurement.isNotEmpty) {
      measurement.removeLast();
      notifyListeners();
    }
  }

  void close() {
    property = null;
    dirty = false;
    measurement.clear();
    _calculate();
  }
}
