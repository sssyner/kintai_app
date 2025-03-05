import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kintai_app/models/location_geofence.dart';

class LocationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _locationsRef(String companyId) =>
      _db.collection('companies').doc(companyId).collection('locations');

  Stream<List<LocationGeofence>> watchLocations(String companyId) {
    return _locationsRef(companyId).snapshots().map(
        (snap) => snap.docs.map(LocationGeofence.fromFirestore).toList());
  }

  Future<void> addLocation(String companyId, LocationGeofence location) {
    return _locationsRef(companyId).add(location.toFirestore());
  }

  Future<void> updateLocation(
      String companyId, String locationId, LocationGeofence location) {
    return _locationsRef(companyId)
        .doc(locationId)
        .update(location.toFirestore());
  }

  Future<void> deleteLocation(String companyId, String locationId) {
    return _locationsRef(companyId).doc(locationId).delete();
  }
}
