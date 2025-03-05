import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/providers/auth_provider.dart';
import 'package:kintai_app/services/company_service.dart';
import 'package:kintai_app/services/profile_image_service.dart';
import 'package:kintai_app/models/company.dart';
import 'package:kintai_app/models/employee.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final companyServiceProvider = Provider((ref) => CompanyService());

final currentUserCompanyProvider = FutureProvider<String?>((ref) {
  final auth = ref.watch(authStateProvider);
  final user = auth.valueOrNull;
  if (user == null) return Future.value(null);
  return ref.read(companyServiceProvider).getUserCompanyId(user.uid);
});

final companyProvider = FutureProvider.family<Company, String>((ref, id) {
  return ref.read(companyServiceProvider).getCompany(id);
});

final currentEmployeeProvider = FutureProvider<Employee?>((ref) async {
  final auth = ref.watch(authStateProvider);
  final user = auth.valueOrNull;
  if (user == null) return null;
  final companyId =
      await ref.read(companyServiceProvider).getUserCompanyId(user.uid);
  if (companyId == null) return null;
  final doc = await FirebaseFirestore.instance
      .collection('companies')
      .doc(companyId)
      .collection('employees')
      .doc(user.uid)
      .get();
  if (!doc.exists) return null;
  return Employee.fromFirestore(doc);
});

final employeesProvider =
    StreamProvider.family<List<Employee>, String>((ref, companyId) {
  return FirebaseFirestore.instance
      .collection('companies')
      .doc(companyId)
      .collection('employees')
      .snapshots()
      .map((snap) => snap.docs.map(Employee.fromFirestore).toList());
});

final inviteCodeProvider =
    FutureProvider.family<String, String>((ref, companyId) {
  return ref.read(companyServiceProvider).getInviteCode(companyId);
});

final profileImageServiceProvider = Provider((ref) => ProfileImageService());
