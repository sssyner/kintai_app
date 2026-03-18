import 'package:cloud_firestore/cloud_firestore.dart';

class Employee {
  final String userId;
  final String name;
  final String email;
  final String role; // 'admin' or 'member'
  final DateTime joinedAt;
  final String? photoUrl;

  Employee({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.joinedAt,
    this.photoUrl,
  });

  bool get isAdmin => role == 'admin';

  factory Employee.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return Employee(
      userId: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? 'member',
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      photoUrl: data['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'email': email,
        'role': role,
        'joinedAt': FieldValue.serverTimestamp(),
        if (photoUrl != null) 'photoUrl': photoUrl,
      };
}
