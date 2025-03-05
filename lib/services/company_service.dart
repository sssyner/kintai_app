import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kintai_app/models/company.dart';
import 'package:uuid/uuid.dart';

class CompanyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<String?> getUserCompanyId(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return doc.data()?['companyId'] as String?;
  }

  Future<Company> getCompany(String companyId) async {
    final doc = await _db.collection('companies').doc(companyId).get();
    return Company.fromFirestore(doc);
  }

  Future<String> createCompany({
    required String name,
    required String uid,
    required String userName,
    required String userEmail,
  }) async {
    final inviteCode = const Uuid().v4().substring(0, 8).toUpperCase();
    final companyRef = _db.collection('companies').doc();
    final companyId = companyRef.id;

    final batch = _db.batch();

    // Create company
    batch.set(companyRef, {
      'name': name,
      'inviteCode': inviteCode,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Add user as admin employee
    batch.set(companyRef.collection('employees').doc(uid), {
      'name': userName,
      'email': userEmail,
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
    });

    // Create user doc
    batch.set(_db.collection('users').doc(uid), {
      'companyId': companyId,
      'name': userName,
      'email': userEmail,
    });

    // Create invite code lookup
    batch.set(_db.collection('inviteCodes').doc(inviteCode), {
      'companyId': companyId,
    });

    await batch.commit();
    return companyId;
  }

  Future<String> joinCompany({
    required String inviteCode,
    required String uid,
    required String userName,
    required String userEmail,
  }) async {
    final codeDoc =
        await _db.collection('inviteCodes').doc(inviteCode.toUpperCase()).get();
    if (!codeDoc.exists) {
      throw Exception('招待コードが見つかりません');
    }
    final companyId = codeDoc.data()!['companyId'] as String;

    final batch = _db.batch();

    // Add as member
    batch.set(
        _db
            .collection('companies')
            .doc(companyId)
            .collection('employees')
            .doc(uid),
        {
          'name': userName,
          'email': userEmail,
          'role': 'member',
          'joinedAt': FieldValue.serverTimestamp(),
        });

    // Create user doc
    batch.set(_db.collection('users').doc(uid), {
      'companyId': companyId,
      'name': userName,
      'email': userEmail,
    });

    await batch.commit();
    return companyId;
  }

  Future<String> getInviteCode(String companyId) async {
    final doc = await _db.collection('companies').doc(companyId).get();
    return doc.data()?['inviteCode'] ?? '';
  }

  /// 従業員を会社から削除し、関連データも削除する
  Future<void> removeEmployee({
    required String companyId,
    required String employeeUid,
  }) async {
    final companyRef = _db.collection('companies').doc(companyId);
    final batch = _db.batch();

    // 従業員ドキュメントを削除
    batch.delete(companyRef.collection('employees').doc(employeeUid));

    // usersコレクションのドキュメントを削除
    batch.delete(_db.collection('users').doc(employeeUid));

    await batch.commit();

    // 打刻データを削除（バッチ上限500件のため分割）
    await _deleteSubcollectionByField(
      companyRef.collection('attendances'),
      'userId',
      employeeUid,
    );

    // 休暇申請データを削除
    await _deleteSubcollectionByField(
      companyRef.collection('leaves'),
      'userId',
      employeeUid,
    );
  }

  /// 指定フィールドが一致するドキュメントをバッチ削除
  Future<void> _deleteSubcollectionByField(
    CollectionReference collection,
    String field,
    String value,
  ) async {
    const batchLimit = 500;
    QuerySnapshot snapshot;
    do {
      snapshot = await collection
          .where(field, isEqualTo: value)
          .limit(batchLimit)
          .get();
      if (snapshot.docs.isEmpty) break;

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (snapshot.docs.length == batchLimit);
  }
}
