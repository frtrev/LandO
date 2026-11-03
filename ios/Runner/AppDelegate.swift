import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String,
       !key.isEmpty, !key.hasPrefix("$("), !key.hasPrefix("YOUR_") {
      GMSServices.provideAPIKey(key)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
