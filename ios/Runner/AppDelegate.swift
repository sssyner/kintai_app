import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("YOUR_API_KEY_HERE")
    GeneratedPluginRegistrant.register(with: self)

    // Firebase初期化後にジオフェンスサービスを登録
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    let geofenceService = KintaiGeofenceService.shared
    if let controller = window?.rootViewController as? FlutterViewController {
      geofenceService.register(with: controller)
    }

    // 位置情報イベントによるバックグラウンド起動時にジオフェンスを再登録
    if launchOptions?[.location] != nil {
      geofenceService.reRegisterFromPersistence()
    }

    return result
  }
}
