import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/models/location_geofence.dart';
import 'package:kintai_app/services/location_service.dart';

final locationServiceProvider = Provider((ref) => LocationService());

final locationsProvider =
    StreamProvider.family<List<LocationGeofence>, String>((ref, companyId) {
  return ref.read(locationServiceProvider).watchLocations(companyId);
});
