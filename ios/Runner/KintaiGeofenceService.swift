import Flutter
import CoreLocation
import FirebaseFirestore
import UserNotifications

/// ネイティブジオフェンスサービス（iOS版）
/// CLCircularRegion で ENTER/EXIT を検知し、Firestore へ直接出退勤を書き込む。
/// アプリkill時でも locationManager delegate が呼ばれるため動作する。
class KintaiGeofenceService: NSObject {
    static let shared = KintaiGeofenceService()

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    private let locationManager = CLLocationManager()
    private lazy var db: Firestore = { Firestore.firestore() }()

    private static let prefsKey = "kintai_geofence_prefs"
    private static let geofencesKey = "registered_geofences"
    private static let userInfoKey = "geofence_user_info"

    func register(with controller: FlutterViewController) {
        methodChannel = FlutterMethodChannel(
            name: "com.kintai/geofencing",
            binaryMessenger: controller.binaryMessenger
        )

        eventChannel = FlutterEventChannel(
            name: "com.kintai/geofencing_events",
            binaryMessenger: controller.binaryMessenger
        )

        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false

        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else {
                result(FlutterMethodNotImplemented)
                return
            }

            switch call.method {
            case "registerGeofences":
                if let args = call.arguments as? [[String: Any]] {
                    let success = self.registerGeofences(locations: args)
                    result(success)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected list of location maps", details: nil))
                }
            case "unregisterAll":
                self.unregisterAll()
                result(nil)
            case "isActive":
                let active = !self.locationManager.monitoredRegions.isEmpty
                result(active)
            case "setUserInfo":
                if let args = call.arguments as? [String: Any],
                   let companyId = args["companyId"] as? String,
                   let userId = args["userId"] as? String {
                    self.setUserInfo(companyId: companyId, userId: userId)
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected companyId and userId", details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        eventChannel?.setStreamHandler(self)
    }

    // MARK: - Geofence Registration

    /// オフィス拠点のジオフェンスを登録（ENTER + EXIT）
    private func registerGeofences(locations: [[String: Any]]) -> Bool {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            NSLog("[KintaiGeofence] CLCircularRegion monitoring not available")
            return false
        }

        // 既存をクリア
        unregisterAll()

        // iOS上限20リージョンに収める
        var locationsToRegister = locations
        if locationsToRegister.count > 20 {
            if let currentLocation = locationManager.location {
                locationsToRegister.sort { a, b in
                    let distA = distanceTo(location: a, from: currentLocation)
                    let distB = distanceTo(location: b, from: currentLocation)
                    return distA < distB
                }
            }
            locationsToRegister = Array(locationsToRegister.prefix(20))
        }

        for loc in locationsToRegister {
            guard let id = loc["id"] as? String,
                  let lat = loc["lat"] as? Double,
                  let lng = loc["lng"] as? Double,
                  let radius = loc["radius"] as? Double else {
                continue
            }

            let clampedRadius = min(radius, locationManager.maximumRegionMonitoringDistance)

            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                radius: clampedRadius,
                identifier: id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true

            locationManager.startMonitoring(for: region)
        }

        // 永続化（再起動後の再登録用）
        persistGeofences(locationsToRegister)

        NSLog("[KintaiGeofence] Registered \(locationsToRegister.count) geofences (ENTER+EXIT)")
        return true
    }

    /// 全ジオフェンスを解除
    private func unregisterAll() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        clearPersistedGeofences()
        NSLog("[KintaiGeofence] Unregistered all geofences")
    }

    /// 端末再起動後にUserDefaultsからジオフェンスを再登録
    func reRegisterFromPersistence() {
        guard let locations = getPersistedGeofences(), !locations.isEmpty else {
            NSLog("[KintaiGeofence] No persisted geofences to re-register")
            return
        }

        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        for loc in locations {
            guard let id = loc["id"] as? String,
                  let lat = loc["lat"] as? Double,
                  let lng = loc["lng"] as? Double,
                  let radius = loc["radius"] as? Double else {
                continue
            }

            let clampedRadius = min(radius, locationManager.maximumRegionMonitoringDistance)
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                radius: clampedRadius,
                identifier: id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            locationManager.startMonitoring(for: region)
        }

        NSLog("[KintaiGeofence] Re-registered \(locations.count) geofences from persistence")
    }

    // MARK: - User Info

    private func setUserInfo(companyId: String, userId: String) {
        let defaults = UserDefaults.standard
        var info = defaults.dictionary(forKey: KintaiGeofenceService.userInfoKey) ?? [:]
        info["companyId"] = companyId
        info["userId"] = userId
        defaults.set(info, forKey: KintaiGeofenceService.userInfoKey)
        NSLog("[KintaiGeofence] User info set: companyId=\(companyId), userId=\(userId)")
    }

    private func getUserInfo() -> (companyId: String, userId: String)? {
        let defaults = UserDefaults.standard
        guard let info = defaults.dictionary(forKey: KintaiGeofenceService.userInfoKey),
              let companyId = info["companyId"] as? String,
              let userId = info["userId"] as? String else {
            return nil
        }
        return (companyId, userId)
    }

    // MARK: - Firestore Operations

    private func handleEnterEvent(regionId: String) {
        guard let userInfo = getUserInfo() else {
            NSLog("[KintaiGeofence] No user info, skipping ENTER event")
            return
        }

        let today = todayString()
        let ref = db.collection("companies").document(userInfo.companyId).collection("attendances")

        // 重複チェック: 今日の出勤が既にあるか
        ref.whereField("userId", isEqualTo: userInfo.userId)
           .whereField("date", isEqualTo: today)
           .limit(to: 1)
           .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    NSLog("[KintaiGeofence] Firestore query error: \(error.localizedDescription)")
                    return
                }

                if let docs = snapshot?.documents, !docs.isEmpty {
                    NSLog("[KintaiGeofence] Already clocked in today, skipping")
                    return
                }

                // 拠点名を取得するためにlocationドキュメントを読む
                self?.getLocationName(companyId: userInfo.companyId, locationId: regionId) { locationName in
                    let data: [String: Any] = [
                        "userId": userInfo.userId,
                        "locationId": regionId,
                        "locationName": locationName ?? regionId,
                        "clockIn": FieldValue.serverTimestamp(),
                        "clockOut": NSNull(),
                        "date": today,
                        "type": "auto_geofence",
                        "memo": NSNull(),
                    ]

                    ref.addDocument(data: data) { error in
                        if let error = error {
                            NSLog("[KintaiGeofence] Failed to clock in: \(error.localizedDescription)")
                        } else {
                            NSLog("[KintaiGeofence] Auto clock-in successful at \(locationName ?? regionId)")
                            self?.sendLocalNotification(
                                title: "自動出勤",
                                body: "\(locationName ?? regionId)に出勤しました"
                            )
                        }
                    }
                }
            }
    }

    private func handleExitEvent(regionId: String) {
        guard let userInfo = getUserInfo() else {
            NSLog("[KintaiGeofence] No user info, skipping EXIT event")
            return
        }

        let today = todayString()
        let ref = db.collection("companies").document(userInfo.companyId).collection("attendances")

        // 今日のclockOutがnullの記録を取得
        ref.whereField("userId", isEqualTo: userInfo.userId)
           .whereField("date", isEqualTo: today)
           .limit(to: 1)
           .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    NSLog("[KintaiGeofence] Firestore query error: \(error.localizedDescription)")
                    return
                }

                guard let doc = snapshot?.documents.first else {
                    NSLog("[KintaiGeofence] No clock-in record found for today, skipping EXIT")
                    return
                }

                let data = doc.data()
                if data["clockOut"] is NSNull || data["clockOut"] == nil {
                    doc.reference.updateData(["clockOut": FieldValue.serverTimestamp()]) { error in
                        if let error = error {
                            NSLog("[KintaiGeofence] Failed to clock out: \(error.localizedDescription)")
                        } else {
                            let locationName = data["locationName"] as? String ?? regionId
                            NSLog("[KintaiGeofence] Auto clock-out successful from \(locationName)")
                            self?.sendLocalNotification(
                                title: "自動退勤",
                                body: "\(locationName)から退勤しました"
                            )
                        }
                    }
                } else {
                    NSLog("[KintaiGeofence] Already clocked out today, skipping")
                }
            }
    }

    private func getLocationName(companyId: String, locationId: String, completion: @escaping (String?) -> Void) {
        db.collection("companies").document(companyId).collection("locations").document(locationId)
            .getDocument { snapshot, error in
                let name = snapshot?.data()?["name"] as? String
                completion(name)
            }
    }

    // MARK: - Local Notification

    private func sendLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Persistence

    private func persistGeofences(_ locations: [[String: Any]]) {
        // Convert to serializable format
        var serializable: [[String: Any]] = []
        for loc in locations {
            var entry: [String: Any] = [:]
            if let id = loc["id"] as? String { entry["id"] = id }
            if let lat = loc["lat"] as? Double { entry["lat"] = lat }
            if let lng = loc["lng"] as? Double { entry["lng"] = lng }
            if let radius = loc["radius"] as? Double { entry["radius"] = radius }
            if let name = loc["name"] as? String { entry["name"] = name }
            serializable.append(entry)
        }
        UserDefaults.standard.set(serializable, forKey: KintaiGeofenceService.geofencesKey)
    }

    private func getPersistedGeofences() -> [[String: Any]]? {
        return UserDefaults.standard.array(forKey: KintaiGeofenceService.geofencesKey) as? [[String: Any]]
    }

    private func clearPersistedGeofences() {
        UserDefaults.standard.removeObject(forKey: KintaiGeofenceService.geofencesKey)
    }

    // MARK: - Helpers

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private func distanceTo(location: [String: Any], from clLocation: CLLocation) -> CLLocationDistance {
        guard let lat = location["lat"] as? Double,
              let lng = location["lng"] as? Double else {
            return .greatestFiniteMagnitude
        }
        return clLocation.distance(from: CLLocation(latitude: lat, longitude: lng))
    }
}

// MARK: - CLLocationManagerDelegate

extension KintaiGeofenceService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        NSLog("[KintaiGeofence] ENTER region: \(circularRegion.identifier)")

        handleEnterEvent(regionId: circularRegion.identifier)

        let eventData: [String: Any] = [
            "event": "enter",
            "locationId": circularRegion.identifier,
            "timestamp": Date().timeIntervalSince1970,
        ]
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(eventData)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        NSLog("[KintaiGeofence] EXIT region: \(circularRegion.identifier)")

        handleExitEvent(regionId: circularRegion.identifier)

        let eventData: [String: Any] = [
            "event": "exit",
            "locationId": circularRegion.identifier,
            "timestamp": Date().timeIntervalSince1970,
        ]
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(eventData)
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        NSLog("[KintaiGeofence] Monitoring failed for region \(region?.identifier ?? "unknown"): \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[KintaiGeofence] Location manager error: \(error.localizedDescription)")
    }
}

// MARK: - FlutterStreamHandler

extension KintaiGeofenceService: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
