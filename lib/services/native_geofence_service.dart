import 'dart:async';
import 'package:flutter/services.dart';

/// ネイティブジオフェンスのMethodChannel/EventChannelラッパー
/// iOS: CLCircularRegion, Android: GeofencingClient を制御する。
class NativeGeofenceService {
  static const _methodChannel = MethodChannel('com.kintai/geofencing');
  static const _eventChannel = EventChannel('com.kintai/geofencing_events');

  Stream<Map<String, dynamic>>? _eventStream;

  /// ジオフェンスイベントのストリーム（アプリフォアグラウンド時のみ）
  Stream<Map<String, dynamic>> get events {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _eventStream!;
  }

  /// オフィス拠点のジオフェンスを登録
  /// [locations] は {id, lat, lng, radius, name} のリスト
  Future<bool> registerGeofences(List<Map<String, dynamic>> locations) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'registerGeofences',
      locations,
    );
    return result ?? false;
  }

  /// 全ジオフェンスを解除
  Future<void> unregisterAll() async {
    await _methodChannel.invokeMethod('unregisterAll');
  }

  /// ジオフェンスが稼働中か
  Future<bool> isActive() async {
    final result = await _methodChannel.invokeMethod<bool>('isActive');
    return result ?? false;
  }

  /// ネイティブ側にユーザー情報を保存（バックグラウンド打刻に必要）
  Future<void> setUserInfo({
    required String companyId,
    required String userId,
  }) async {
    await _methodChannel.invokeMethod('setUserInfo', {
      'companyId': companyId,
      'userId': userId,
    });
  }
}
