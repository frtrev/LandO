import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:lando/screens/map_screen.dart';
import 'map_screen_test.dart' show MapHarness, MemoryRepository;
import 'support/assistant_fixtures.dart' show exampleProperty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/geolocator');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<void> mount(WidgetTester tester, MemoryRepository repo) async {
    GoogleMapsFlutterPlatform.instance = MapHarness();
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          repository: repo,
          themeMode: ThemeMode.light,
          onTheme: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, Object> position() => {
    'latitude': 32.7767,
    'longitude': -96.7970,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'accuracy': 5.0,
    'altitude': 0.0,
    'heading': 0.0,
    'speed': 0.0,
    'speed_accuracy': 0.0,
  };
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('empty startup asks permission and centers on current location', (
    tester,
  ) async {
    var requests = 0, fixes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return 0;
        case 'requestPermission':
          requests++;
          return 2;
        case 'isLocationServiceEnabled':
          return true;
        case 'getCurrentPosition':
          fixes++;
          return position();
      }
      return null;
    });
    await mount(tester, MemoryRepository());
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.initialCameraPosition.target, const LatLng(32.7767, -96.7970));
    expect(map.myLocationEnabled, true);
    expect(requests, 1);
    expect(fixes, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'unselected saved properties and a deleted last selection still start at GPS',
    (tester) async {
      var fixes = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkPermission') return 2;
        if (call.method == 'isLocationServiceEnabled') return true;
        if (call.method == 'getCurrentPosition') {
          fixes++;
          return position();
        }
        return null;
      });
      for (final selected in ['', 'deleted-property']) {
        final repo = MemoryRepository();
        await repo.save(exampleProperty());
        repo.preferences['lastProperty'] = selected;
        await mount(tester, repo);
        expect(
          tester
              .widget<GoogleMap>(find.byType(GoogleMap))
              .initialCameraPosition
              .target,
          const LatLng(32.7767, -96.7970),
        );
        expect(find.text('Your land, in perspective.'), findsOneWidget);
        expect(repo.properties, hasLength(1));
        await tester.pumpWidget(const SizedBox());
      }
      expect(fixes, 2);
    },
  );

  testWidgets(
    'Explore hides the welcome card and can leave a selected property safely',
    (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkPermission') return 2;
        if (call.method == 'isLocationServiceEnabled') return true;
        if (call.method == 'getCurrentPosition') return position();
        return null;
      });
      final repo = MemoryRepository();
      await repo.save(exampleProperty());
      repo.preferences['lastProperty'] = '';
      await mount(tester, repo);
      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();
      expect(find.text('Your land, in perspective.'), findsNothing);
      expect(find.text('Explore the map'), findsOneWidget);
      expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).polygons,
        isEmpty,
      );
      expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).scrollGesturesEnabled,
        true,
      );
      await tester.tap(find.text('Properties'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Explore'), findsOneWidget);
      await tester.tap(find.text('My pasture'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).polygons,
        isNotEmpty,
      );
      final marker = tester
          .widget<GoogleMap>(find.byType(GoogleMap))
          .markers
          .firstWhere((m) => m.draggable);
      marker.onDragEnd!(const LatLng(30.00005, -98));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Properties'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Explore'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Unsaved property changes'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(repo.preferences['lastProperty'], 'property');
      expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).polygons,
        isNotEmpty,
      );
      await tester.tap(find.text('Properties'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Explore'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(repo.preferences['lastProperty'], '');
      expect(repo.properties, hasLength(1));
      expect(find.text('Your land, in perspective.'), findsNothing);
      expect(find.text('Explore the map'), findsOneWidget);
      expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).polygons,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await mount(tester, repo);
      expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .initialCameraPosition
            .target,
        const LatLng(32.7767, -96.7970),
      );
      expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).polygons,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'saved property and recovered draft keep their own view without requesting GPS',
    (tester) async {
      var fixes = 0, requests = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkPermission') return 2;
        if (call.method == 'requestPermission') {
          requests++;
          return 2;
        }
        if (call.method == 'getCurrentPosition') {
          fixes++;
          return position();
        }
        return true;
      });
      for (final draft in [false, true]) {
        final repo = MemoryRepository(), property = exampleProperty();
        if (draft) {
          repo.preferences['draft'] = jsonEncode(property.toJson());
        } else {
          await repo.save(property);
        }
        await mount(tester, repo);
        expect(
          tester
              .widget<GoogleMap>(find.byType(GoogleMap))
              .initialCameraPosition
              .target,
          LatLng(property.latitude, property.longitude),
        );
        await tester.pumpWidget(const SizedBox());
      }
      expect(fixes, 0);
      expect(requests, 0);
    },
  );

  testWidgets('denied permission leaves an usable map and no GPS request', (
    tester,
  ) async {
    var fixes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isLocationServiceEnabled') return true;
      if (call.method == 'getCurrentPosition') {
        fixes++;
        return position();
      }
      return 0;
    });
    await mount(tester, MemoryRepository());
    expect(fixes, 0);
    expect(
      tester.widget<GoogleMap>(find.byType(GoogleMap)).myLocationEnabled,
      false,
    );
    expect(find.textContaining('Location permission denied'), findsOneWidget);
    expect(find.byTooltip('Search address'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a late automatic GPS fix does not replace a manually moved map',
    (tester) async {
      final fix = Completer<Map<String, Object>>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkPermission') return 2;
        if (call.method == 'isLocationServiceEnabled') return true;
        if (call.method == 'getCurrentPosition') return fix.future;
        return null;
      });
      await mount(tester, MemoryRepository());
      const moved = CameraPosition(target: LatLng(40, -100), zoom: 12);
      tester.widget<GoogleMap>(find.byType(GoogleMap)).onCameraMove!(moved);
      fix.complete(position());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .initialCameraPosition
            .target,
        moved.target,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
