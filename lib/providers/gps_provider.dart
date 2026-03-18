import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kintai_app/services/gps_service.dart';

final gpsServiceProvider = Provider((ref) => GpsService());

final currentPositionProvider = FutureProvider.autoDispose<Position>((ref) {
  return ref.read(gpsServiceProvider).getCurrentPosition();
});
