import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/property_controller.dart';
import '../models/property.dart';
import '../services/place_search.dart';
import '../services/map_measurement_label.dart';
import '../services/property_repository.dart';
import '../widgets/layer_editor_panel.dart';
import '../widgets/data_transfer_sheet.dart';
import '../widgets/assistant/property_chat_sheet.dart';
import '../widgets/assistant/ai_settings_sheet.dart';
import '../services/assistant/api_key_store.dart';
import '../widgets/property_layers_sheet.dart';

class MapScreen extends StatefulWidget {
  final PropertyRepository repository;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onTheme;
  const MapScreen({
    super.key,
    required this.repository,
    required this.themeMode,
    required this.onTheme,
  });
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  late final PropertyController state = PropertyController(widget.repository);
  final search = PlaceSearch();
  final ApiKeyStore aiKeyStore = SecureApiKeyStore();
  final Map<String, BitmapDescriptor> markerIcons = {};
  final Set<String> pendingIcons = {};
  GoogleMapController? map;
  CameraPosition camera = const CameraPosition(
    target: LatLng(30.2672, -97.7431),
    zoom: 17,
  );
  MapType mapType = MapType.satellite;
  bool editing = true,
      locationGranted = false,
      details = false,
      busy = false,
      allowPop = false;
  bool boundaryVisible = true;
  bool showMapLabels = true;
  List<MapMeasurementLabel> measurementLabels = [];
  final Map<String, BitmapDescriptor> measurementIcons = {};
  final Set<String> pendingMeasurementIcons = {};
  bool _locating = false;
  bool _transferring = false;
  int _navigationVersion = 0;
  bool get measuring => state.activeLayer != null;
  String length(double meters) => state.property?.metric == true
      ? '${meters.toStringAsFixed(1)} m'
      : '${(meters / 0.3048).toStringAsFixed(1)} ft';
  LatLng ll(BoundaryPoint p) => LatLng(p.latitude, p.longitude);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state.addListener(refresh);
    initialize();
  }

  Future<void> initialize() async {
    try {
      await state.restore();
      await restoreTheme();
      final p = await Geolocator.checkPermission();
      if (mounted) {
        setState(
          () => locationGranted =
              p == LocationPermission.always ||
              p == LocationPermission.whileInUse,
        );
      }
      centerProperty();
      // Recovered drafts and saved properties always keep their saved view.
      if (mounted &&
          state.property == null &&
          (await widget.repository.list()).isEmpty) {
        await locate(automatic: true);
      }
    } catch (e) {
      message('Could not restore app data: $e');
    }
  }

  Future<void> restoreTheme() async {
    final saved = await widget.repository.preference('theme');
    if (mounted) {
      widget.onTheme(
        ThemeMode.values.firstWhere(
          (v) => v.name == saved,
          orElse: () => ThemeMode.system,
        ),
      );
    }
  }

  void refresh() {
    measurementLabels = [
      for (final layer in state.property?.layers ?? <PropertyLayer>[])
        if ((state.layerErrors[layer.id] ?? []).isEmpty)
          ?MapMeasurementLabel.forLayer(
            layer,
            metric: state.property!.metric,
            geometry: state.geometry,
            areaResult: state.areaResults[layer.id],
            distance: state.pathLengths[layer.id],
          ),
    ];
    for (final label in measurementLabels) {
      if (!measurementIcons.containsKey(label.iconKey) &&
          pendingMeasurementIcons.add(label.iconKey)) {
        buildMeasurementIcon(label);
      }
    }
    for (final point in state.property?.points ?? <BoundaryPoint>[]) {
      if (!markerIcons.containsKey(point.label) &&
          pendingIcons.add(point.label)) {
        buildMarker(point.label);
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> buildMeasurementIcon(MapMeasurementLabel label) async {
    final title = TextPainter(
      text: TextSpan(
        text: label.name,
        style: const TextStyle(color: Color(0xffe5eee8), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 145);
    final value = TextPainter(
      text: TextSpan(
        text: label.value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = math.max(title.width, value.width) + 18;
    final height = title.height + value.height + 12;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(2);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(.5, .5, width - 1, height - 1),
      const Radius.circular(7),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xe620332c));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = (label.area ? Colors.orangeAccent : Colors.lightBlueAccent)
            .withValues(alpha: .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    title.paint(canvas, Offset((width - title.width) / 2, 5));
    value.paint(canvas, Offset((width - value.width) / 2, title.height + 6));
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (width * 2).ceil(),
      (height * 2).ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    pendingMeasurementIcons.remove(label.iconKey);
    if (!mounted || bytes == null) return;
    setState(() {
      if (measurementIcons.length >= 128) {
        final active = measurementLabels.map((l) => l.iconKey).toSet();
        measurementIcons.removeWhere((key, _) => !active.contains(key));
      }
      measurementIcons[label.iconKey] = BitmapDescriptor.bytes(
        bytes.buffer.asUint8List(),
        width: width,
        height: height,
      );
    });
  }

  Future<void> buildMarker(String label) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(36, 36),
      32,
      Paint()..color = const Color(0xff153e32),
    );
    canvas.drawCircle(
      const Offset(36, 36),
      29,
      Paint()..color = const Color(0xffb5ff68),
    );
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xff103c2c),
          fontSize: label.length > 2 ? 18 : 26,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(36 - text.width / 2, 36 - text.height / 2));
    final picture = recorder.endRecording();
    final image = await picture.toImage(72, 72);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes != null && mounted) {
      setState(
        () => markerIcons[label] = BitmapDescriptor.bytes(
          bytes.buffer.asUint8List(),
          width: 36,
          height: 36,
        ),
      );
    }
    image.dispose();
    picture.dispose();
    pendingIcons.remove(label);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(refresh);
    state.dispose();
    search.dispose();
    map?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Preserve unsaved edits independently from the last explicit save.
    if (lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.paused) {
      recoverDraft();
    }
  }

  Future<void> recoverDraft() async {
    if (_transferring) return;
    captureCamera();
    await state.persistDraft();
    if (state.storageError != null) {
      message(state.storageError!);
    }
  }

  void showCoordinateLockMessage() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          editing
              ? 'Property coordinates unlocked'
              : 'Property coordinates locked',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void toggleCoordinateLock() {
    setState(() => editing = !editing);
    showCoordinateLockMessage();
  }

  void moveBoundaryPoint(String id, LatLng position) {
    if (!editing || busy || measuring) return;
    state.move(id, position.latitude, position.longitude);
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> safe(Future<void> Function() task) async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    try {
      await task();
    } catch (e) {
      message(e.toString());
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void captureCamera() {
    final p = state.property;
    if (p != null) {
      p.latitude = camera.target.latitude;
      p.longitude = camera.target.longitude;
      p.zoom = camera.zoom;
      p.bearing = camera.bearing;
      p.tilt = camera.tilt;
    }
  }

  Future<void> save() async {
    captureCamera();
    await state.save();
    if (!state.dirty) {
      message('Property saved on this device');
    }
  }

  Future<bool> canLeave() async {
    if (!state.dirty) {
      return true;
    }
    final decision = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Unsaved property changes'),
        content: Text(
          state.canSave
              ? 'Save your changes before continuing?'
              : 'Finish or fix invalid boundaries, areas or measurements, or discard these changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'cancel'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            child: const Text('Discard'),
          ),
          if (state.canSave)
            FilledButton(
              onPressed: () => Navigator.pop(c, 'save'),
              child: const Text('Save'),
            ),
        ],
      ),
    );
    if (decision == 'save') {
      await save();
      return !state.dirty;
    }
    if (decision == 'discard') {
      final id = state.property?.id;
      await state.discardDraft();
      final saved = await widget.repository.list();
      final previous = saved.where((p) => p.id == id).firstOrNull;
      if (previous != null) {
        await state.open(previous);
      } else {
        state.close();
      }
      return true;
    }
    return false;
  }

  void centerProperty() {
    final p = state.property;
    if (p == null) {
      return;
    }
    _navigationVersion++;
    camera = CameraPosition(
      target: LatLng(p.latitude, p.longitude),
      zoom: p.zoom,
      bearing: p.bearing,
      tilt: p.tilt,
    );
    map?.animateCamera(CameraUpdate.newCameraPosition(camera));
  }

  Future<String?> textDialog(
    String title,
    String initial, {
    bool multiline = false,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: multiline ? 2000 : 100,
          maxLines: multiline ? 4 : 1,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: multiline
              ? null
              : (v) {
                  if (v.trim().isNotEmpty) {
                    Navigator.pop(c, v.trim());
                  }
                },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty || multiline) {
                Navigator.pop(c, controller.text.trim());
              }
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
    // Dialog route transitions finish after the Future completes.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    return result;
  }

  Future<void> create() async {
    if (!await canLeave() || !mounted) {
      return;
    }
    final name = await textDialog('Name your property', 'My Land');
    if (name == null || !mounted) {
      return;
    }
    final bounds = await map?.getVisibleRegion();
    final lat = camera.target.latitude, lon = camera.target.longitude;
    final dy = bounds == null
        ? 0.0004
        : ((bounds.northeast.latitude - bounds.southwest.latitude).abs() * .18)
              .clamp(.00005, .005);
    final span = bounds == null
        ? .002
        : (bounds.northeast.longitude - bounds.southwest.longitude + 360) % 360;
    final dx = (span * .18).clamp(.00005, .005);
    double wrap(double value) => (value + 540) % 360 - 180;
    final points = [
      LatLng((lat + dy).clamp(-85, 85), wrap(lon - dx)),
      LatLng((lat + dy).clamp(-85, 85), wrap(lon + dx)),
      LatLng((lat - dy).clamp(-85, 85), wrap(lon + dx)),
      LatLng((lat - dy).clamp(-85, 85), wrap(lon - dx)),
    ];
    state.create(
      name,
      List.generate(
        4,
        (i) => BoundaryPoint(
          id: newId(),
          label: pointLabel(i),
          latitude: points[i].latitude,
          longitude: points[i].longitude,
        ),
      ),
      lat,
      lon,
      camera.zoom,
    );
    setState(() {
      editing = true;
      state.finishLayer();
    });
    message('Starter rectangle only. Drag each corner to map your boundary.');
  }

  Future<void> locate({bool automatic = false}) async {
    if (_locating || !mounted) return;
    final version = automatic ? _navigationVersion : ++_navigationVersion;
    final initialView = camera;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        message(
          'Enable Location Services to center the map. You can still search or pan.',
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final granted =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!mounted) return;
      setState(() => locationGranted = granted);
      if (!granted) {
        message(
          permission == LocationPermission.deniedForever
              ? 'Location denied. Enable it in app settings, or search and pan.'
              : 'Location permission denied. You can still search or pan.',
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: automatic ? LocationAccuracy.medium : LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      if (automatic) {
        final saved = await widget.repository.list();
        if (!mounted ||
            version != _navigationVersion ||
            state.property != null ||
            saved.isNotEmpty ||
            (camera.target.latitude - initialView.target.latitude).abs() >
                .000001 ||
            (camera.target.longitude - initialView.target.longitude).abs() >
                .000001 ||
            (camera.zoom - initialView.zoom).abs() > .001 ||
            (camera.bearing - initialView.bearing).abs() > .001 ||
            (camera.tilt - initialView.tilt).abs() > .001) {
          return;
        }
      }
      if (!mounted) return;
      camera = CameraPosition(
        target: LatLng(position.latitude, position.longitude),
        zoom: 18,
      );
      await map?.animateCamera(CameraUpdate.newCameraPosition(camera));
    } on Object {
      message(
        'Could not determine your location. You can still search or pan, or try My location again.',
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> findAddress() async {
    _navigationVersion++;
    final query = await textDialog('Search address or place', '');
    if (query == null) {
      return;
    }
    final results = await search.search(
      query,
      latitude: camera.target.latitude,
      longitude: camera.target.longitude,
    );
    if (!mounted) {
      return;
    }
    if (results.isEmpty) {
      message(
        'Google did not return a matching address or place. You can try a postal code or pan to the location.',
      );
      return;
    }
    final place = await showModalBottomSheet<PlaceResult>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Search results · Google Maps')),
            ...results.map(
              (r) => ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(r.name),
                onTap: () => Navigator.pop(c, r),
              ),
            ),
          ],
        ),
      ),
    );
    if (place != null && mounted) {
      final resolved = await search.resolve(place);
      if (!mounted) return;
      camera = CameraPosition(
        target: LatLng(resolved.latitude!, resolved.longitude!),
        zoom: 18,
      );
      await map?.animateCamera(CameraUpdate.newCameraPosition(camera));
    }
  }

  Future<void> properties() async {
    final saved = await widget.repository.list();
    if (!mounted) {
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: 420,
          child: Column(
            children: [
              ListTile(
                title: const Text('Your properties'),
                trailing: FilledButton.icon(
                  onPressed: () => Navigator.pop(c, 'new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Create'),
                ),
              ),
              Expanded(
                child: saved.isEmpty
                    ? const Center(child: Text('No saved properties yet.'))
                    : ListView(
                        children: saved
                            .map(
                              (p) => ListTile(
                                leading: const Icon(Icons.landscape_outlined),
                                title: Text(p.name),
                                subtitle: Text(
                                  '${p.points.length} points · saved ${p.modified.toLocal().toString().split('.').first}',
                                ),
                                onTap: () => Navigator.pop(c, p.id),
                                trailing: IconButton(
                                  tooltip: 'Delete property',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      Navigator.pop(c, 'delete:${p.id}'),
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) {
      return;
    }
    if (selected == 'new') {
      await create();
      return;
    }
    if (selected.startsWith('delete:')) {
      final id = selected.substring(7);
      final p = saved.firstWhere((p) => p.id == id);
      if (!mounted) {
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: Text('Delete ${p.name}?'),
          content: const Text(
            'This removes the saved property from this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await widget.repository.delete(id);
        if (state.property?.id == id) {
          await state.discardDraft();
          state.close();
        }
      }
    } else if (await canLeave()) {
      // Reload from storage so discarding edits cannot leak through object aliases.
      final fresh = await widget.repository.list();
      await state.open(fresh.firstWhere((p) => p.id == selected));
      centerProperty();
    }
  }

  Future<void> editPoint(BoundaryPoint point, {String? layerId}) async {
    if (layerId == null && !editing) {
      showCoordinateLockMessage();
      return;
    }
    final lat = TextEditingController(text: point.latitude.toStringAsFixed(8));
    final lon = TextEditingController(text: point.longitude.toStringAsFixed(8));
    String? error;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          scrollable: true,
          title: Text(
            '${layerId == null ? 'Boundary' : 'Layer'} point ${point.label}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: lat,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Latitude (−90 to 90)',
                ),
              ),
              TextField(
                controller: lon,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Longitude (−180 to 180)',
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(c).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: layerId == null && state.property!.points.length <= 3
                  ? null
                  : () {
                      if (layerId == null) {
                        state.remove(point.id);
                      } else {
                        state.removeLayerPoint(layerId, point.id);
                      }
                      Navigator.pop(c);
                    },
              child: const Text('Delete'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final a = double.tryParse(lat.text),
                    b = double.tryParse(lon.text);
                if (a == null ||
                    b == null ||
                    !a.isFinite ||
                    !b.isFinite ||
                    a.abs() > 90 ||
                    b.abs() > 180) {
                  update(() => error = 'Enter valid decimal coordinates.');
                  return;
                }
                if (layerId == null) {
                  state.move(point.id, a, b);
                } else {
                  state.moveLayerPoint(layerId, point.id, a, b);
                }
                Navigator.pop(c);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      lat.dispose();
      lon.dispose();
    });
  }

  Future<void> insertPoint() async {
    final property = state.property;
    if (property == null) {
      message('Create or open a property first.');
      return;
    }
    final layer = state.activeLayer;
    if (layer == null && !editing) {
      showCoordinateLockMessage();
      return;
    }
    final points = layer?.points ?? property.points;
    if (points.length < 2) {
      message('Tap the map to add at least two points first.');
      return;
    }
    final edges = layer?.kind == LayerKind.distance
        ? points.length - 1
        : points.length;
    final index = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Insert a point between…')),
            ...List.generate(
              edges,
              (i) => ListTile(
                title: Text(
                  '${points[i].label} → ${points[(i + 1) % points.length].label}',
                ),
                subtitle: const Text(
                  'Starts at the geodesic midpoint; drag to adjust',
                ),
                onTap: () => Navigator.pop(c, i),
              ),
            ),
          ],
        ),
      ),
    );
    if (index == null) {
      return;
    }
    if (layer != null) {
      state.insertLayerPoint(layer.id, index);
    } else {
      if (editing) state.insertAfter(index);
    }
  }

  Future<void> askLando() async {
    if (state.property == null) {
      message('Create or open a property first.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => PropertyChatSheet(
        currentProperty: () => state.property!,
        repository: widget.repository,
        keyStore: aiKeyStore,
      ),
    );
  }

  Future<void> aiSettings() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          AiSettingsSheet(keyStore: aiKeyStore, repository: widget.repository),
    );
  }

  Future<void> transferData() async {
    await recoverDraft();
    if (state.storageError != null || !mounted) return;
    _transferring = true;
    _navigationVersion++;
    try {
      final restored = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => DataTransferSheet(repository: widget.repository),
      );
      if (restored == true) {
        _navigationVersion++;
        await state.reloadAfterRestore();
        await restoreTheme();
        centerProperty();
        message('Backup restored.');
      }
    } finally {
      _transferring = false;
    }
  }

  Future<void> settings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Map & preferences',
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final type in [
                        MapType.satellite,
                        MapType.hybrid,
                        MapType.normal,
                      ])
                        ChoiceChip(
                          label: Text(
                            type == MapType.normal ? 'Standard' : type.name,
                          ),
                          selected: mapType == type,
                          onSelected: (_) {
                            setState(() => mapType = type);
                            update(() {});
                          },
                        ),
                    ],
                  ),
                  if (state.property != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Metric units'),
                      subtitle: const Text('Saved with this property'),
                      value: state.property!.metric,
                      onChanged: (value) {
                        state.property!.metric = value;
                        state.changed();
                        update(() {});
                      },
                    ),
                  DropdownButtonFormField<ThemeMode>(
                    initialValue: widget.themeMode,
                    decoration: const InputDecoration(labelText: 'Appearance'),
                    items: ThemeMode.values
                        .map(
                          (v) =>
                              DropdownMenuItem(value: v, child: Text(v.name)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        widget.onTheme(v);
                        safe(
                          () =>
                              widget.repository.setPreference('theme', v.name),
                        );
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('LandO assistant settings'),
                    subtitle: const Text('Configure your LandO assistant'),
                    onTap: aiSettings,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('Backup & restore'),
                    subtitle: const Text(
                      'Save, share, or restore all app data',
                    ),
                    onTap: () {
                      Navigator.pop(c);
                      safe(transferData);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Map-derived planning estimates. Not a legal survey or confirmation of ownership. Use a licensed surveyor for legal boundaries.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget summary() {
    final p = state.property!, r = state.result;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (state.dirty)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text('Unsaved'),
                  ),
                IconButton(
                  tooltip: editing
                      ? 'Lock boundary editing'
                      : 'Unlock boundary editing',
                  onPressed: toggleCoordinateLock,
                  icon: Icon(
                    editing ? Icons.lock_open_outlined : Icons.lock_outline,
                  ),
                ),
                IconButton(
                  tooltip: 'Hide boundary panel',
                  onPressed: () => setState(() => boundaryVisible = false),
                  icon: const Icon(Icons.close),
                ),
                IconButton(
                  tooltip: details ? 'Collapse details' : 'Expand details',
                  onPressed: () => setState(() => details = !details),
                  icon: Icon(details ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
            if (p.layers.isNotEmpty)
              TextButton.icon(
                onPressed: () => safe(showLayers),
                icon: const Icon(Icons.layers_outlined),
                label: Text(
                  '${p.layers.where((l) => l.kind == LayerKind.area).length} areas · ${p.layers.where((l) => l.kind == LayerKind.distance).length} measurements',
                ),
              ),
            if (state.layerErrors.values.any((errors) => errors.isNotEmpty))
              Text(
                'Finish or remove invalid areas and measurements before saving.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!r.valid)
              Text(
                r.errors.join('\n'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else
              Wrap(
                spacing: 24,
                runSpacing: 6,
                children: [
                  stat(
                    p.metric
                        ? '${r.hectares!.toStringAsFixed(3)} ha'
                        : '${r.acres!.toStringAsFixed(3)} acres',
                    'Total area',
                  ),
                  stat(
                    p.metric
                        ? '${r.squareMeters!.toStringAsFixed(1)} m²'
                        : '${r.squareFeet!.toStringAsFixed(0)} sq ft',
                    'Surface area',
                  ),
                  stat(length(r.perimeterMeters!), 'Perimeter'),
                ],
              ),
            const SizedBox(height: 6),
            const Text(
              'Map-derived planning estimate · Not a legal survey',
              style: TextStyle(fontSize: 11),
            ),
            if (details)
              SizedBox(
                height: math.min(260, MediaQuery.sizeOf(context).height * .30),
                child: ListView(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${p.points.length} boundary points'),
                      subtitle: Text(
                        p.description.isEmpty
                            ? (editing
                                  ? 'Tap a point to edit its coordinates.'
                                  : 'Property coordinates locked. Unlock to edit.')
                            : p.description,
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) => safe(() async {
                          final text = await textDialog(
                            v == 'name'
                                ? 'Rename property'
                                : 'Property description',
                            v == 'name' ? p.name : p.description,
                            multiline: v == 'description',
                          );
                          if (text != null) {
                            if (v == 'name') {
                              p.name = text;
                            } else {
                              p.description = text;
                            }
                            state.changed();
                          }
                        }),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'name',
                            child: Text('Rename'),
                          ),
                          const PopupMenuItem(
                            value: 'description',
                            child: Text('Edit description'),
                          ),
                        ],
                      ),
                    ),
                    if (r.valid)
                      Text(
                        '${r.squareMeters!.toStringAsFixed(2)} m² · ${r.hectares!.toStringAsFixed(4)} ha\n${r.squareFeet!.toStringAsFixed(1)} sq ft · ${r.acres!.toStringAsFixed(4)} acres\n${r.perimeterMeters!.toStringAsFixed(1)} m · ${(r.perimeterMeters! / .3048).toStringAsFixed(1)} ft\nCenter: ${r.center!.lat.toStringAsFixed(6)}, ${r.center!.lon.toStringAsFixed(6)}',
                      ),
                    ...List.generate(p.points.length, (i) {
                      final point = p.points[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(child: Text(point.label)),
                        title: Text(
                          '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          r.valid
                              ? '${point.label} → ${p.points[(i + 1) % p.points.length].label}: ${length(r.segments[i])}'
                              : 'Segment unavailable for invalid boundary',
                        ),
                        onTap: () => editPoint(point),
                        trailing: IconButton(
                          tooltip: 'Insert after ${point.label}',
                          icon: const Icon(Icons.add_location_alt_outlined),
                          onPressed: editing
                              ? () => state.insertAfter(i)
                              : null,
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget stat(String value, String caption) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      Text(caption, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final p = state.property;
    final points = p?.points ?? <BoundaryPoint>[];
    final bottom = MediaQuery.paddingOf(context).bottom;
    return PopScope(
      canPop: allowPop || !state.dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await canLeave() && mounted) {
          setState(() => allowPop = true);
          if (context.mounted) {
            Navigator.maybePop(context);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LandO',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              Text(
                p?.name ?? 'Map it. Measure it. Plan it.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          actions: [
            if (p != null)
              IconButton(
                tooltip: 'Ask LandO about my property',
                onPressed: busy ? null : askLando,
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
            IconButton(
              tooltip: 'Search address',
              onPressed: busy ? null : () => safe(findAddress),
              icon: const Icon(Icons.search),
            ),
            if (p != null)
              IconButton(
                tooltip: 'Save property',
                onPressed: busy || state.saving || !state.canSave
                    ? null
                    : () => safe(save),
                icon: Icon(
                  state.saving ? Icons.hourglass_top : Icons.save_outlined,
                ),
              ),
            IconButton(
              tooltip: 'Settings',
              onPressed: settings,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              GoogleMap(
                initialCameraPosition: camera,
                mapType: mapType,
                onMapCreated: (controller) {
                  map = controller;
                  if (state.property != null) {
                    centerProperty();
                  } else {
                    controller.moveCamera(
                      CameraUpdate.newCameraPosition(camera),
                    );
                  }
                },
                onCameraMove: (position) => camera = position,
                onCameraIdle: () {
                  if (_transferring) return;
                  captureCamera();
                  if (state.dirty) {
                    state.persistDraft();
                  }
                },
                myLocationEnabled: locationGranted,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                padding: EdgeInsets.only(
                  bottom: p == null
                      ? 100
                      : (measuring || boundaryVisible ? 200 : 12),
                  top: 12,
                ),
                onTap: (point) {
                  if (measuring && !busy) {
                    state.addLayerPoint(point.latitude, point.longitude);
                  }
                },
                markers: {
                  if (showMapLabels)
                    for (final label in measurementLabels)
                      if (measurementIcons[label.iconKey] != null)
                        Marker(
                          markerId: MarkerId('measurement-label-${label.id}'),
                          position: LatLng(label.latitude, label.longitude),
                          icon: measurementIcons[label.iconKey]!,
                          anchor: label.area
                              ? const Offset(.5, .5)
                              : const Offset(.5, 1.1),
                          zIndexInt: 1,
                          consumeTapEvents: true,
                        ),
                  if (!measuring)
                    for (final point in points)
                      Marker(
                        markerId: MarkerId(point.id),
                        position: ll(point),
                        draggable: editing && !measuring && !busy,
                        zIndexInt: 2,
                        anchor: const Offset(.5, .5),
                        icon:
                            markerIcons[point.label] ??
                            BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueGreen,
                            ),
                        infoWindow: InfoWindow(
                          title: point.label,
                          snippet:
                              '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
                          onTap: () => editPoint(point),
                        ),
                        onTap: () {
                          if (!measuring) {
                            editPoint(point);
                          }
                        },
                        onDrag: (position) =>
                            moveBoundaryPoint(point.id, position),
                        onDragEnd: (position) =>
                            moveBoundaryPoint(point.id, position),
                      ),
                  if (state.activeLayer != null)
                    for (final point in state.activeLayer!.points)
                      Marker(
                        markerId: MarkerId('layer-${point.id}'),
                        position: ll(point),
                        draggable: !busy,
                        zIndexInt: 3,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          state.activeLayer!.kind == LayerKind.area
                              ? BitmapDescriptor.hueOrange
                              : BitmapDescriptor.hueAzure,
                        ),
                        infoWindow: InfoWindow(title: point.label),
                        onTap: () =>
                            editPoint(point, layerId: state.activeLayer!.id),
                        onDrag: (position) => state.moveLayerPoint(
                          state.activeLayer!.id,
                          point.id,
                          position.latitude,
                          position.longitude,
                        ),
                        onDragEnd: (position) => state.moveLayerPoint(
                          state.activeLayer!.id,
                          point.id,
                          position.latitude,
                          position.longitude,
                        ),
                      ),
                },
                polygons: {
                  if (points.length >= 3)
                    Polygon(
                      polygonId: const PolygonId('property'),
                      points: points.map(ll).toList(),
                      geodesic: true,
                      strokeWidth: 3,
                      strokeColor: state.result.valid
                          ? const Color(0xffa5ff59)
                          : Colors.redAccent,
                      fillColor:
                          (state.result.valid ? Colors.greenAccent : Colors.red)
                              .withValues(alpha: .18),
                    ),
                  for (final layer in p?.layers ?? <PropertyLayer>[])
                    if (layer.kind == LayerKind.area &&
                        layer.points.length >= 3)
                      Polygon(
                        polygonId: PolygonId(layer.id),
                        points: layer.points.map(ll).toList(),
                        geodesic: true,
                        strokeWidth: state.activeLayerId == layer.id ? 4 : 2,
                        strokeColor: state.layerErrors[layer.id]!.isEmpty
                            ? Colors.orangeAccent
                            : Colors.redAccent,
                        fillColor: Colors.orange.withValues(alpha: .22),
                        zIndex: 1,
                        consumeTapEvents: !measuring,
                        onTap: () => state.selectLayer(layer.id),
                      ),
                },
                polylines: {
                  for (final layer in p?.layers ?? <PropertyLayer>[])
                    if (layer.points.length >= 2 &&
                        (layer.kind == LayerKind.distance ||
                            layer.points.length < 3))
                      Polyline(
                        polylineId: PolylineId(layer.id),
                        points: layer.points.map(ll).toList(),
                        geodesic: true,
                        width: state.activeLayerId == layer.id ? 5 : 3,
                        color: layer.kind == LayerKind.area
                            ? Colors.orangeAccent
                            : Colors.lightBlueAccent,
                        zIndex: 2,
                        consumeTapEvents: !measuring,
                        onTap: () => state.selectLayer(layer.id),
                      ),
                },
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'locate',
                      tooltip: 'My location',
                      onPressed: busy || _locating ? null : () => safe(locate),
                      child: const Icon(Icons.my_location),
                    ),
                    if (p != null)
                      FloatingActionButton.small(
                        heroTag: 'center',
                        tooltip: 'Saved map view',
                        onPressed: centerProperty,
                        child: const Icon(Icons.center_focus_strong),
                      ),
                    if (p != null)
                      FloatingActionButton.small(
                        heroTag: 'map-labels',
                        tooltip: showMapLabels
                            ? 'Hide area & distance labels'
                            : 'Show area & distance labels',
                        onPressed: () =>
                            setState(() => showMapLabels = !showMapLabels),
                        child: Icon(
                          showMapLabels
                              ? Icons.label
                              : Icons.label_off_outlined,
                        ),
                      ),
                  ],
                ),
              ),
              if (busy)
                const Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 680,
                      maxHeight: math.max(0, constraints.maxHeight - 24),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (state.activeLayer != null)
                            LayerEditorPanel(
                              layer: state.activeLayer!,
                              measurement: layerMeasurement(state.activeLayer!),
                              errors:
                                  state.layerErrors[state.activeLayerId] ?? [],
                              onUndo: state.undoLayerPoint,
                              onClear: state.clearLayer,
                              onDone: state.finishLayer,
                              onDelete: () =>
                                  safe(() => deleteLayer(state.activeLayer!)),
                              onEditPoint: (point) => editPoint(
                                point,
                                layerId: state.activeLayerId,
                              ),
                              onInsertPoint: (index) => state.insertLayerPoint(
                                state.activeLayerId!,
                                index,
                              ),
                            ),
                          if (p != null && !measuring && boundaryVisible)
                            summary()
                          else if (p == null)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Your land, in perspective.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Find your property, then map its corners.',
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed: busy
                                          ? null
                                          : () => safe(create),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Create Property'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Material(
          elevation: 8,
          child: Padding(
            padding: EdgeInsets.fromLTRB(4, 6, 4, bottom + 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                tool(
                  Icons.folder_outlined,
                  'Properties',
                  () => safe(properties),
                ),
                tool(
                  Icons.edit_location_alt,
                  'Boundary',
                  p == null
                      ? null
                      : () => setState(() {
                          boundaryVisible = measuring ? true : !boundaryVisible;
                          state.finishLayer();
                        }),
                  active: boundaryVisible && p != null && !measuring,
                ),
                tool(
                  Icons.add_location_alt_outlined,
                  'Add point',
                  p == null || (!measuring && !editing)
                      ? null
                      : () => safe(insertPoint),
                ),
                tool(
                  Icons.straighten,
                  'Measure',
                  p == null
                      ? null
                      : () => safe(() => startLayer(LayerKind.distance)),
                  active: state.activeLayer?.kind == LayerKind.distance,
                ),
                tool(
                  Icons.layers_outlined,
                  'Layers',
                  p == null ? null : () => safe(showLayers),
                  active: measuring,
                ),
                tool(
                  Icons.info_outline,
                  'Details',
                  p == null
                      ? null
                      : () => setState(() {
                          details = boundaryVisible ? !details : true;
                          boundaryVisible = true;
                          state.finishLayer();
                        }),
                  active: details && boundaryVisible && !measuring,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String layerMeasurement(PropertyLayer layer) {
    if ((state.layerErrors[layer.id] ?? []).isNotEmpty) {
      return layer.kind == LayerKind.area
          ? 'Area not yet valid'
          : 'Path not yet valid';
    }
    if (layer.kind == LayerKind.distance) {
      return length(state.pathLengths[layer.id]!);
    }
    final area = state.areaResults[layer.id]!;
    return state.property!.metric
        ? '${area.squareMeters!.toStringAsFixed(1)} m² · ${area.hectares!.toStringAsFixed(3)} ha\n${length(area.perimeterMeters!)} perimeter'
        : '${area.acres!.toStringAsFixed(3)} acres · ${area.squareFeet!.toStringAsFixed(0)} sq ft\n${length(area.perimeterMeters!)} perimeter';
  }

  Future<void> startLayer(LayerKind kind) async {
    if (state.property == null || !mounted) {
      return;
    }
    final name = await textDialog(
      kind == LayerKind.area ? 'Name this area' : 'Name this measurement',
      kind == LayerKind.area
          ? 'Area ${state.property!.layers.where((l) => l.kind == kind).length + 1}'
          : 'Measurement ${state.property!.layers.where((l) => l.kind == kind).length + 1}',
    );
    if (name == null || !mounted) {
      return;
    }
    state.startLayer(kind, name);
  }

  Future<void> deleteLayer(PropertyLayer layer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${layer.name}?'),
        content: const Text(
          'This removes the shape from this property. Save the property to keep this change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      state.deleteLayer(layer.id);
    }
  }

  Future<void> showLayers() async {
    if (state.property == null) {
      return;
    }
    final action =
        await showModalBottomSheet<
          ({String action, String? id, LayerKind? kind})
        >(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          builder: (c) => PropertyLayersSheet(
            controller: state,
            measurement: layerMeasurement,
            onCreate: (kind) =>
                Navigator.pop(c, (action: 'create', id: null, kind: kind)),
            onEdit: (layer) =>
                Navigator.pop(c, (action: 'edit', id: layer.id, kind: null)),
            onRename: (layer) =>
                Navigator.pop(c, (action: 'rename', id: layer.id, kind: null)),
            onDelete: (layer) =>
                Navigator.pop(c, (action: 'delete', id: layer.id, kind: null)),
          ),
        );
    if (action == null || !mounted) {
      return;
    }
    if (action.action == 'create') {
      await startLayer(action.kind!);
      return;
    }
    final layer = state.property!.layers.firstWhere(
      (layer) => layer.id == action.id,
    );
    if (action.action == 'edit') {
      state.selectLayer(layer.id);
    }
    if (action.action == 'delete') {
      await deleteLayer(layer);
    }
    if (action.action == 'rename') {
      final name = await textDialog(
        'Rename ${layer.kind == LayerKind.area ? 'area' : 'measurement'}',
        layer.name,
      );
      if (name != null) {
        state.renameLayer(layer.id, name);
      }
    }
  }

  Widget tool(
    IconData icon,
    String label,
    VoidCallback? action, {
    bool active = false,
  }) => Expanded(
    child: TextButton(
      onPressed: busy ? null : action,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8),
        backgroundColor: active
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    ),
  );
}
