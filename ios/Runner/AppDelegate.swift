import Flutter
import UIKit
import GoogleMaps
import GooglePlaces

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var placeSession: GMSAutocompleteSessionToken?
  private var suggestionIDs = Set<String>()
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
        .setMethodCallHandler { [weak self] call, result in
          guard let self else { result(FlutterError(code: "places_unavailable", message: "Search unavailable.", details: nil)); return }
          let args = call.arguments as? [String: Any] ?? [:]
          let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String ?? ""
          guard !key.isEmpty, !key.hasPrefix("$("), !key.hasPrefix("YOUR_") else {
            result(FlutterError(code: "places_not_configured", message: "Google Places key is missing.", details: nil)); return
          }
          if call.method == "resolve" {
            guard let id = args["placeId"] as? String, self.suggestionIDs.contains(id), let token = self.placeSession else {
              result(FlutterError(code: "places_selection_expired", message: "Search again to select this result.", details: nil)); return
            }
            self.placeSession = nil
            self.suggestionIDs.removeAll()
            let fields = [GMSPlaceProperty.formattedAddress, .coordinate].map { $0.rawValue }
            let request = GMSFetchPlaceRequest(placeID: id, placeProperties: fields, sessionToken: token)
            GMSPlacesClient.shared().fetchPlace(with: request) { place, error in
              if let error = error as NSError? {
                self.placesError(error, result: result); return
              }
              guard let place else { result(FlutterError(code: "places_error", message: "No location returned.", details: nil)); return }
              result(["name": place.formattedAddress ?? args["name"] as? String ?? "Place", "latitude": place.coordinate.latitude, "longitude": place.coordinate.longitude, "placeId": id])
            }
            return
          }
          guard call.method == "search" else { result(FlutterMethodNotImplemented); return }
          guard let query = args["query"] as? String,
                !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                query.count <= 300 else {
            result(FlutterError(code: "invalid_query", message: "Enter an address or place (up to 300 characters).", details: nil)); return
          }
          self.placeSession = nil
          self.suggestionIDs.removeAll()
          let token = GMSAutocompleteSessionToken()
          let request = GMSAutocompleteRequest(query: query)
          request.sessionToken = token
          let filter = GMSAutocompleteFilter()
          // A qualified address should not be pulled towards a distant map view.
          if !query.contains(","), let lat = args["latitude"] as? Double, let lon = args["longitude"] as? Double {
            filter.locationBias = GMSPlaceCircularLocationOption(CLLocationCoordinate2D(latitude: lat, longitude: lon), 50000)
          }
          request.filter = filter
          GMSPlacesClient.shared().fetchAutocompleteSuggestions(from: request) { suggestions, error in
            if let error = error as NSError? { self.placesError(error, result: result); return }
            let places = (suggestions ?? []).compactMap { $0.placeSuggestion }.prefix(5)
            if places.isEmpty {
              self.textSearch(query: query, args: args, result: result); return
            }
            self.placeSession = token
            self.suggestionIDs = Set(places.map { $0.placeID })
            result(places.map { ["name": $0.attributedFullText.string, "placeId": $0.placeID] })
          }
        }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LandOLocalModels") {
      FlutterMethodChannel(name: "lando/local_models", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          guard call.method == "excludeFromBackup",
                let args = call.arguments as? [String: String],
                let path = args["path"],
                path.hasPrefix(NSHomeDirectory() + "/Library/") else {
            result(FlutterMethodNotImplemented); return
          }
          do {
            var url = URL(fileURLWithPath: path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            result(nil)
          } catch {
            result(FlutterError(code: "backup_exclusion", message: "Could not prepare model storage.", details: nil))
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

  private func placesError(_ error: NSError, result: FlutterResult) {
    // Never forward SDK descriptions, which may contain credentials.
    result(FlutterError(code: "places_error", message: "Google Places search failed.", details: ["statusCode": error.code]))
  }

  private func textSearch(query: String, args: [String: Any], result: @escaping FlutterResult) {
    let fields = [GMSPlaceProperty.name, .formattedAddress, .coordinate].map { $0.rawValue }
    let request = GMSPlaceSearchByTextRequest(textQuery: query, placeProperties: fields)
    request.maxResultCount = 5
    if !query.contains(","), let lat = args["latitude"] as? Double, let lon = args["longitude"] as? Double {
      request.locationBias = GMSPlaceCircularLocationOption(CLLocationCoordinate2D(latitude: lat, longitude: lon), 50000)
    }
    GMSPlacesClient.shared().searchByText(with: request) { places, error in
      if let error = error as NSError? { self.placesError(error, result: result); return }
      result((places ?? []).map { ["name": $0.formattedAddress ?? $0.name ?? "Place", "latitude": $0.coordinate.latitude, "longitude": $0.coordinate.longitude] as [String: Any] })
    }
  }

}
