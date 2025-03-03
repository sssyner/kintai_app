import 'package:cloud_firestore/cloud_firestore.dart';

class LocationGeofence {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radius; // meters
  final bool isActive;

  LocationGeofence({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radius,
    required this.isActive,
  });

  factory LocationGeofence.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return LocationGeofence(
      id: doc.id,
      name: data['name'] ?? '',
      lat: (data['lat'] as num?)?.toDouble() ?? 0,
      lng: (data['lng'] as num?)?.toDouble() ?? 0,
      radius: (data['radius'] as num?)?.toDouble() ?? 200,
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'isActive': isActive,
      };
}
