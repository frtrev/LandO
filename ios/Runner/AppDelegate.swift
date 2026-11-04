import Flutter
import UIKit
import GoogleMaps
import GooglePlaces

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String,
       !key.isEmpty, !key.hasPrefix("$("), !key.hasPrefix("YOUR_") {
      GMSServices.provideAPIKey(key)
      GMSPlacesClient.provideAPIKey(key)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LandOPlaces") {
      FlutterMethodChannel(name: "lando/places", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          guard call.method == "search" else { result(FlutterMethodNotImplemented); return }
          guard let args = call.arguments as? [String: Any],
                let query = args["query"] as? String,
                !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                query.count <= 300 else {
            result(FlutterError(code: "invalid_query", message: "Enter an address or place (up to 300 characters).", details: nil)); return
          }
          let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String ?? ""
          guard !key.isEmpty, !key.hasPrefix("$("), !key.hasPrefix("YOUR_") else {
            result(FlutterError(code: "places_not_configured", message: "Google Places key is missing.", details: nil)); return
          }
          let fields = [GMSPlaceProperty.name, .formattedAddress, .coordinate].map { $0.rawValue }
          let request = GMSPlaceSearchByTextRequest(textQuery: query, placeProperties: fields)
          request.maxResultCount = 5
          if let lat = args["latitude"] as? Double, let lon = args["longitude"] as? Double {
            request.locationBias = GMSPlaceCircularLocationOption(CLLocationCoordinate2D(latitude: lat, longitude: lon), 50000)
          }
          GMSPlacesClient.shared().searchByText(with: request) { places, error in
            if let error = error as NSError? {
              // Never forward SDK descriptions, which may contain credentials.
              result(FlutterError(code: "places_error", message: "Google Places search failed.", details: ["statusCode": error.code])); return
            }
            result((places ?? []).map { place in
              ["name": place.formattedAddress ?? place.name ?? "Place", "latitude": place.coordinate.latitude, "longitude": place.coordinate.longitude] as [String: Any]
            })
          }
        }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LandOConfig") {
      FlutterMethodChannel(name: "lando/config", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          if call.method == "mapsConfigured" {
            let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String ?? ""
            result(!key.isEmpty && !key.hasPrefix("$(") && !key.hasPrefix("YOUR_"))
          } else {
            result(FlutterMethodNotImplemented)
          }
        }
    }
  }
}
