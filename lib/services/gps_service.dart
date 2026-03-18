import 'dart:io';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kintai_app/models/location_geofence.dart';
import 'package:kintai_app/services/native_geofence_service.dart';

class GpsService {
  final _nativeGeofence = NativeGeofenceService();

  /// ネイティブジオフェンスを登録（OSレベルのENTER/EXIT検知）
  Future<bool> registerGeofences(List<LocationGeofence> fences) async {
    final activeFences = fences.where((f) => f.isActive).toList();
    if (activeFences.isEmpty) return false;

    final data = activeFences
        .map((f) => {
              'id': f.id,
              'lat': f.lat,
              'lng': f.lng,
              'radius': f.radius,
              'name': f.name,
            })
        .toList();

    return _nativeGeofence.registerGeofences(data);
  }

  /// ネイティブジオフェンスを全解除
  Future<void> unregisterGeofences() async {
    await _nativeGeofence.unregisterAll();
  }

  /// 「常に許可」を取得（ジオフェンスに必要）
  Future<void> ensureAlwaysPermission() async {
    // Step 1: まずforeground（使用中のみ）を取得
    var status = await Permission.locationWhenInUse.status;
    if (status.isDenied) {
      status = await Permission.locationWhenInUse.request();
      if (status.isDenied) {
        throw Exception('位置情報の権限が必要です');
      }
    }
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      throw Exception('設定から位置情報を許可してください');
    }

    // Step 2: background（常に）を取得
    var bgStatus = await Permission.locationAlways.status;
    if (!bgStatus.isGranted) {
      // Android: 明示的にACCESS_BACKGROUND_LOCATIONをリクエスト
      // iOS: 「常に許可」へのアップグレードダイアログ
      bgStatus = await Permission.locationAlways.request();
    }
    // 「常に」が取れなくてもエラーにはしない（手動打刻は使える）
    // ただしジオフェンスは動かない
  }

  Future<Position> getCurrentPosition() async {
    var status = await Permission.locationWhenInUse.status;
    if (status.isDenied) {
      status = await Permission.locationWhenInUse.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        throw Exception('位置情報の権限が必要です');
      }
    }
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      throw Exception('設定から位置情報を許可してください');
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('位置情報サービスが無効です');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 10));
  }

  double calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  bool isInsideGeofence(double lat, double lng, LocationGeofence fence) {
    final distance = calculateDistance(lat, lng, fence.lat, fence.lng);
    return distance <= fence.radius;
  }

  LocationGeofence? findNearestGeofence(
      double lat, double lng, List<LocationGeofence> fences) {
    if (fences.isEmpty) return null;
    final activeFences = fences.where((f) => f.isActive).toList();
    if (activeFences.isEmpty) return null;

    LocationGeofence? nearest;
    double minDistance = double.infinity;
    for (final fence in activeFences) {
      final d = calculateDistance(lat, lng, fence.lat, fence.lng);
      if (d < minDistance) {
        minDistance = d;
        nearest = fence;
      }
    }
    return nearest;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
}
