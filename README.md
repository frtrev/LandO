# LandO

**Map it. Measure it. Plan it.** A Flutter Android/iOS property mapper. Phase 1 only: satellite maps, ordered editable boundaries, WGS84 measurements, independent distance paths, and local SQLite storage. All boundaries and measurements are **map-derived planning estimates, not legal surveys**.

## Requirements and status

- Flutter 3.44+ / compatible Dart SDK, Android SDK, and Xcode for iOS. Generated and validated with Flutter 3.47.5 / Dart 3.13.4; exact SDK constraints are in `pubspec.yaml`.
- Android application ID `com.neotheone.lando`, minimum Android API 24.
- iOS bundle ID `app.neotheone.lando`, deployment target iOS 15+.
- Google Cloud billing and platform Maps keys. Maps and search require connectivity. Saved geometry and calculations live on the device.
- Address search requires deploying the included server proxy and passing its HTTPS URL to Flutter.

This implementation requires real-device acceptance testing with configured Google Maps keys before Phase 1 can be declared complete. No Phase 2 or AI screens are included. The original brief references Sheet Music Rookie; its source/design was not supplied, so this project uses a standalone Material 3 architecture.

## Google Maps configuration

Enable **Maps SDK for Android**, **Maps SDK for iOS**, and **Places API (New)** in your Google Cloud project.

1. Copy `android/maps.properties.example` to `android/maps.properties`. Set `MAPS_API_KEY` to the Android key. Restrict it to Android applications: package `com.neotheone.lando` and the signing certificate SHA-1 for each intended debug/release build. Restrict API access to Maps SDK for Android.
2. Copy `ios/Flutter/MapsSecrets.xcconfig.example` to `ios/Flutter/MapsSecrets.xcconfig`. Set `GOOGLE_MAPS_API_KEY`. Restrict this separate key to iOS bundle `app.neotheone.lando` and Maps SDK for iOS. Both Debug and Release configurations include the local file; Profile uses Release.
3. Create a **separate server key**, restricted to Places API (New) and your server's static egress IP where available. Keep it on the server. Mobile application restrictions are unsuitable for an ordinary server REST key.
4. Configure signing in Xcode for your own team and provision Android release signing before distribution. The generated Android release build currently uses debug signing for development.

A build without a configured Maps SDK key displays setup guidance. The real credential files are git-ignored. Never commit keys, signing files, or environment files. Keys embedded in mobile Maps SDK builds are identifiable by clients; platform and API restrictions are essential.

Official setup: [Flutter Google Maps](https://developers.google.com/maps/flutter-package/config), [Android key restrictions](https://developers.google.com/maps/documentation/android-sdk/get-api-key), [iOS setup](https://developers.google.com/maps/documentation/ios-sdk/config), [Places Text Search](https://developers.google.com/maps/documentation/places/web-service/text-search).

### Address search proxy

The dependency-free Node 22+ server in `server/places_proxy.mjs` forwards Text Search (New) with a minimal field mask (`places.displayName,places.formattedAddress,places.location`). The app displays results over Google Maps and moves the camera to the selected address. No Google REST key is distributed in the app.

Set `GOOGLE_PLACES_API_KEY` through your deployment's secret manager/environment, then run:

```sh
node server/places_proxy.mjs
```

The process listens on loopback port 8080 (`PORT` overrides it). Expose `/search` through an HTTPS reverse proxy. Requests are `POST {"textQuery":"a complete address"}`; responses are `{"places":[...]}` in the Places API format. Configure the app:

```sh
flutter pub get
flutter run --dart-define=PLACES_PROXY_URL=https://YOUR_HOST/search
```

The server includes input limits, a timeout and per-connection-IP request limiting. For public deployment, enforce authentication/attestation and rate limits at the gateway, configure Google quotas and budget alerts, and protect against proxy bypass. Behind a reverse proxy, the built-in rate limit sees that proxy's IP; use gateway limits for individual clients. The sample does not provide user accounts or app attestation. Do not publish an unrestricted billable search endpoint.

## Using LandO

1. Search or pan to your land. Use the location button to request foreground location permission and return to your position. Permission denial does not block map editing.
2. Choose **Create Property**, enter its name, and adjust the four initial corners. The initial rectangle is a viewport-relative starter shape, not an inferred parcel boundary.
3. Drag lettered corners in **Boundary** mode. Tap a corner to enter decimal latitude/longitude (eight digits shown in editor, six in details) or delete it. At least three corners remain.
4. **Add point** asks which edge to split. A geodesic midpoint is inserted in that exact position, with a new permanent label: A → B → E → C → D → A. Move it to the intended corner. Labels extend through Z, AA, AB, etc. No automatic geographic sorting occurs.
5. Expand **Details** for every coordinate, segment, area unit, perimeter unit, and a geographic center. Its menu edits the property name and description. Settings changes map type, theme, and the property's preferred units. Imperial is the default.
6. **Measure** starts an independent open path: tap the map repeatedly, see cumulative distance, undo, or clear. It does not alter property coordinates. Press Done to leave measurement mode; its overlay remains until cleared or another property is opened.
7. Press the Save icon to persist changes. Properties lists saved entries and supports open/delete. Returning to the app restores the most recently opened property or an unsaved recovery draft.

Unsaved navigation prompts offer Save, Discard, and Keep editing. Invalid geometry can be edited or discarded, but cannot overwrite a valid saved property. A separate recovery draft is written after 300 ms of inactivity while editing and on app suspension/camera idle. Recovery does not replace the explicit save. As with any local storage, immediate process termination before a write completes can lose the latest fraction of a second. Data is local to this installation; uninstalling removes it. Measurement paths are temporary and are not saved.

## Geometry and architecture

- `lib/models/property.dart`: UUID points with permanent labels; list position is the boundary sequence. Property records include name, description, timestamps, unit preference and full map camera.
- `lib/services/geometry_service.dart`: UI-independent WGS84 Vincenty distance calculations using `geobase`, and numerical ellipsoidal polygon area. It integrates the exact ellipsoid surface primitive along geodesic edges with composite Simpson quadrature (at least eight intervals, at most 250 m per interval). Subtracting a common primitive baseline reduces cancellation. This is neither a raw lat/lon shoelace calculation nor a spherical acreage approximation.
- Validation rejects out-of-range/nonfinite coordinates, points within 1 mm of one another, crossings/touches between nonadjacent edges, adjacent backtracking, fewer than three points, and areas below 0.01 m². Intersection checks use sampled geodesics in a local gnomonic projection; near-tangent/near-coincident configurations at submillimeter separation are numerically ambiguous and should be adjusted.
- Supported property domain: latitude within ±85°, every point within 100 km of the first. Out-of-domain properties are explicitly rejected rather than given misleading totals. Antimeridian properties are supported. Distances are ellipsoidal surface distances, not terrain/slope distances. Center is a circular-longitude vertex mean, useful for labels/centering and not guaranteed inside a concave polygon.
- `lib/services/property_repository.dart`: SQLite with transactional explicit save and last-property preference; ordered points serialized in a JSON record. Geometry is recalculated on open. Versioned database schema allows future migration.
- `lib/controllers/property_controller.dart`: editing, measurements, validation state, explicit saves and recovery drafts.
- `lib/screens/map_screen.dart`: Google Maps and responsive floating Material 3 panels, separate map and measurement overlays.

No ads, subscription requirement, AI arithmetic, or OpenAI credentials.

## Validation

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
node --test server/places_proxy.test.mjs
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

Calculation fixtures in `test/geographiclib_fixtures.json` were generated independently using GeographicLib Python 2.1. They cover equatorial, Texas, concave, antimeridian, high-latitude and large-property polygons, both windings, and assert area against references with tolerance `1e-7 * area + 0.002 m²`, perimeter within 1 mm. Additional tests cover invalid polygons, insertion, unit conversions, independent paths, search error handling, SQLite reopen/draft recovery, and a map UI harness covering ordered insertion and small landscape layout. The harness does not simulate native map gestures or imagery. Regenerate fixtures with `tools/generate_geometry_fixtures.py` after installing `geographiclib==2.1` in a temporary Python environment.

### Device acceptance still required

On **both a physical Android and iOS device**, check satellite/hybrid/standard tiles with restricted keys; place search; location allowed/denied; pan/zoom/rotate; viewport starter rectangle; live drag polygon and totals; insertion/deletion/manual coordinates; concave and invalid boundaries; open distance path; multi-property save/rename/delete; force quit and relaunch; recovered drafts; save/discard prompts; light/dark mode; small-phone landscape and tablet layouts. Compare a known parcel with surveyed reference coordinates. SDK compilation and automated tests cannot establish imagery, permissions or gesture correctness on a real device.
