# LandO

**Map it. Measure it. Plan it.** A Flutter Android/iOS property mapper. Satellite maps, ordered editable boundaries, WGS84 measurements, named areas and multiple saved distance paths, and local SQLite storage. All boundaries and measurements are **map-derived planning estimates, not legal surveys**.

## Requirements and status

- Flutter 3.44+ / compatible Dart SDK, Android SDK, and Xcode for iOS. Generated and validated with Flutter 3.47.5 / Dart 3.13.4; exact SDK constraints are in `pubspec.yaml`.
- Android application ID `com.neotheone.lando`, minimum Android API 24.
- iOS bundle ID `app.neotheone.lando`, deployment target iOS 15+.
- Google Cloud billing and platform Maps keys. Maps and search require connectivity. Saved geometry and calculations live on the device.
- Address search requires deploying the included server proxy and passing its HTTPS URL to Flutter.

This implementation requires real-device acceptance testing with configured Google Maps keys before Phase 1 can be declared complete. Saved areas and distance paths extend the mapping milestone; Ask LandO adds read-only property questions and deterministic planning estimates; drawing automation, supplier prices and project-management screens are not included. The original brief references Sheet Music Rookie; its source/design was not supplied, so this project uses a standalone Material 3 architecture.

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
6. **Layers → Add area** creates a named area. Tap the map to add its corners; the polygon closes automatically after three points. Its area and perimeter update independently of the property boundary. Areas use orange outlines; distance paths use blue.
7. **Measure** (or **Layers → Add measurement**) creates a named open path. Tap two or more points to measure cumulative length. Repeat to create multiple paths. Each path remains separate and does not include a closing segment.
8. In the active shape's panel, Undo removes the latest point and Clear removes all of its points. Drag markers or expand Coordinates and tap a row to manually edit/delete a point. **Add point** splits a selected edge of the active shape; paths do not offer a closing edge. Press Done when the shape is valid. Tap a saved shape on the map, or choose it in **Layers**, to continue editing. The Layers menu also offers Rename and Delete for each item. Boundary returns to editing the property outline.
9. Press the Save icon to persist the **entire property, including all areas and measurements**. Properties lists saved entries and supports open/delete. Returning to the app restores the most recently opened property or an unsaved recovery draft.

Unsaved navigation prompts offer Save, Discard, and Keep editing. Invalid geometry can be edited or discarded, but cannot overwrite a valid saved property. A separate recovery draft is written after 300 ms of inactivity while editing and on app suspension/camera idle. Recovery does not replace the explicit save. As with any local storage, immediate process termination before a write completes can lose the latest fraction of a second. Data is local to this installation; uninstalling removes it. Named areas and measurement paths are stored in the same SQLite property record and included in recovery drafts. Existing property records without layers open normally with an empty collection. No database reset or table migration is needed. Incomplete shapes and invalid area polygons prevent an explicit save; finish, fix, or delete them first. Other valid property data remains preserved in its last saved version. Areas and paths are associated with a property but are not clipped to its boundary, subtracted from its acreage, or restricted to being inside it; overlapping areas are measured independently.

## Ask LandO about my property

Open a property, then tap the sparkle button **Ask LandO about my property** in the map's top bar. The chat panel has suggested questions, follow-up conversation, app-calculated result cards and a Stop request action. Close the panel to return to the map.

### Setup

1. Open **Settings → LandO assistant settings** (or **AI settings** inside chat).
2. Choose **Gemini (Google)** or **OpenAI** in **AI provider**. Enter that provider's own API key and model ID, then press **Save AI settings**. You can save the provider/model before adding a key; chat remains disabled until that provider has a key.
3. Provider credentials are stored separately in iOS Keychain with device-only, unlocked accessibility or encrypted Android secure storage. No API key is stored in property SQLite records, build flags or source code. A blank key field keeps that provider's stored key. Remove API key deletes only the provider currently shown. Switching providers preserves the other provider's key and model.
4. Default models are `gemini-3.6-flash` for Gemini and `gpt-5.6-terra` for OpenAI. Model IDs remain editable. Defaults were checked against [Google's Gemini model documentation](https://aistudio.google.com/docs/models/gemini-3.6-flash) and [OpenAI's model documentation](https://developers.openai.com/api/docs/models/gpt-5.6-terra). An existing installation without a provider preference retains OpenAI as its default and continues using its existing key/model without a migration.
5. Send a question such as “How many acres is my property?”, “How long is my Driveway measurement?”, or “How much gravel for Driveway, 12 feet wide and 4 inches deep?”

**Gemini with an existing Google Cloud project:** create a **Gemini Developer API** key in [Google AI Studio](https://aistudio.google.com/apikey). You can import your existing Cloud project into AI Studio and create the key there; follow [Google's API key/project instructions](https://aistudio.google.com/docs/api-key). The key needs Generative Language API access and the model must be available to your project. Use a separate key from the Google Maps SDK keys. This integration calls `generativelanguage.googleapis.com` using the `x-goog-api-key` header; it does not use Vertex AI endpoints, OAuth/service-account files or your Maps SDK credentials. **No OpenAI key or account is required when Gemini is selected.**

API usage, quota, billing and model availability belong to the selected provider's account/project. LandO never silently falls back to the other provider, and never sends one provider's key to another. Live acceptance still requires a real provider key; automated API tests use mocked HTTP responses and never contact or charge an account. Verify a real response after entering a valid key, including secure key storage across a device restart.

### How answers work

OpenAI uses [Responses function calling](https://developers.openai.com/api/docs/guides/function-calling); Gemini uses the [Generate Content API](https://aistudio.google.com/api-reference/generate-content) with the same local calculation tools. Every question starts by calling the app's property-summary tool against an immutable snapshot of the **current property, including unsaved edits**. Numeric lookup and project calculations run in Dart, independently of the model:

- Property area, perimeter, ordered segments and coordinates.
- Saved named area measurements and independent open-path lengths.
- Gravel surface area, volume and US short tons for a saved path or supplied length, width and depth.
- Topsoil/fill volume for a saved area at a supplied depth.
- Fence posts and spans for the property boundary, a saved area/path, or a supplied length and maximum spacing.
- Cost line items, labor, tax and contingency using explicit quantities, currency and user-supplied rates.

The assistant is instructed to ask for missing or ambiguous dimensions, spacing or rates. It has no web access, satellite image input, current supplier prices, legal parcel lookup or authority to edit the map. Invalid geometry returns validation errors instead of totals. Expand the **Calculated by LandO** cards to inspect the actual results, units and assumptions independently of generated prose. Historical cards show when their property snapshot was taken; a new question recalculates against the latest geometry.

Material assumptions: uniform width/depth, no compaction or waste allowance. Gravel density defaults to **1.4 US short tons per cubic yard only as a labeled planning assumption** when no density is supplied; actual density should come from the supplier. Imperial tool dimensions are length/width in feet and depth in inches; metric dimensions are length/width in meters and depth in centimeters. Fence counts are length-based estimates without gates, corners, bracing or terrain allowances. Cost tax applies to materials plus labor; contingency applies after tax. Generated explanations can still be mistaken: the displayed app results are the calculation record.

### Privacy and local history

Sending a question transmits the question, recent conversation and structured property information (including property/layer names and description) directly to your **selected provider** over HTTPS. Switching providers carries the recent conversation to the newly selected provider on your next question; the chat panel identifies the active provider and assistant replies record which provider answered. Exact boundary coordinates are returned when the boundary-detail tool is requested. The assistant sends no property or conversation data before you send a question. OpenAI requests set `store: false`; this disables Responses application-state storage, **not all provider retention**, as described in [OpenAI's data controls](https://developers.openai.com/api/docs/guides/your-data). Gemini uses stateless Generate Content requests without creating a server-side conversation; Google data handling depends on your account and service terms. Neither provider is claimed to have zero retention.

Up to 40 chat messages and their app-calculated result records are saved locally per property, separately from explicit property saves. Up to 24 recent messages are sent as context. Clear chat history deletes that property's local conversation; deleting a property deletes its local chat too. Closing chat or Stop request closes the current request client and ignores late results; already-processed API work may still be billed. History is retained if a request fails, so its question can be retried. Mapping and calculations remain usable with neither provider configured.

The tool loop is bounded to eight requests, sixteen local calls and a two-minute elapsed budget, with per-request timeouts and no automatic billable retries. OpenAI Responses replay tool results and encrypted reasoning within a turn. Gemini replays the complete model content, including thought signatures, and returns matching function-call IDs for tool continuation; hidden thought text is not displayed or saved as an answer. Android app backup is disabled to prevent restoring encrypted credentials without the corresponding Keystore key; property and chat data remain local to the installation.

## Geometry and architecture

- `lib/models/property.dart`: UUID points with permanent labels; list position is the boundary sequence. Property records include name, description, timestamps, unit preference, full map camera, and a collection of UUID-identified named area/path layers, each with its own ordered coordinates.
- `lib/services/geometry_service.dart`: UI-independent WGS84 Vincenty distance calculations using `geobase`, and numerical ellipsoidal polygon area. It integrates the exact ellipsoid surface primitive along geodesic edges with composite Simpson quadrature (at least eight intervals, at most 250 m per interval). Subtracting a common primitive baseline reduces cancellation. This is neither a raw lat/lon shoelace calculation nor a spherical acreage approximation.
- Validation rejects out-of-range/nonfinite coordinates, points within 1 mm of one another, crossings/touches between nonadjacent edges, adjacent backtracking, fewer than three points, and areas below 0.01 m². Intersection checks use sampled geodesics in a local gnomonic projection; near-tangent/near-coincident configurations at submillimeter separation are numerically ambiguous and should be adjusted.
- Supported property domain: latitude within ±85°, every point within 100 km of the first. Out-of-domain properties are explicitly rejected rather than given misleading totals. Antimeridian properties are supported. Distances are ellipsoidal surface distances, not terrain/slope distances. Center is a circular-longitude vertex mean, useful for labels/centering and not guaranteed inside a concave polygon.
- `lib/services/property_repository.dart`: SQLite with transactional explicit save and last-property preference; ordered points serialized in a JSON record. Geometry is recalculated on open. Versioned database schema allows future migration.
- `lib/controllers/property_controller.dart`: editing, measurements, validation state, explicit saves and recovery drafts.
- `lib/screens/map_screen.dart`: Google Maps and responsive floating Material 3 panels, separate map and measurement overlays.

No ads or mandatory subscriptions. Mapping works without AI. No developer-owned AI credentials are embedded in the app.

## Validation

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
node --test server/places_proxy.test.mjs
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

Calculation fixtures in `test/geographiclib_fixtures.json` were generated independently using GeographicLib Python 2.1. They cover equatorial, Texas, concave, antimeridian, high-latitude and large-property polygons, both windings, and assert area against references with tolerance `1e-7 * area + 0.002 m²`, perimeter within 1 mm. Additional tests cover invalid polygons, insertion, unit conversions, independent paths, search error handling, SQLite reopen/draft recovery, multiple-area/path SQLite round trips, legacy property compatibility, invalid-layer save protection and draft recovery, and map UI harnesses covering drawing, saving, reopening, dragging, ordered insertion and small landscape layouts. Assistant tests cover deterministic project quantities/costs, tool argument errors, stateless Responses continuation, bounded loops, credential redaction, per-property history, cancellation, secure-settings UI and chat layout. Gemini tests cover complete function-call/thought-signature replay, parallel tool results, errors and truncation; provider tests cover isolated secure key slots, legacy OpenAI compatibility, Gemini-only setup and provider/model switching. The harness does not simulate native map gestures or imagery. Regenerate fixtures with `tools/generate_geometry_fixtures.py` after installing `geographiclib==2.1` in a temporary Python environment.

### Device acceptance still required

On **both a physical Android and iOS device**, check satellite/hybrid/standard tiles with restricted keys; place search; location allowed/denied; pan/zoom/rotate; viewport starter rectangle; live drag polygon and totals; insertion/deletion/manual coordinates; concave and invalid boundaries; multiple named areas and open distance paths; edit/rename/delete each layer; save and reopen a property with all of its shapes; multi-property save/rename/delete; force quit and relaunch; recovered drafts; save/discard prompts; light/dark mode; small-phone landscape and tablet layouts. Compare a known parcel with surveyed reference coordinates. SDK compilation and automated tests cannot establish imagery, permissions or gesture correctness on a real device.
