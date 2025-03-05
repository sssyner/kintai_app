import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

class ProfileImageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) {
    return _picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
  }

  Future<String> uploadAndSave({
    required String companyId,
    required String userId,
    required File imageFile,
  }) async {
    final ref = _storage.ref('profiles/$companyId/$userId.jpg');
    await ref.putFile(
      imageFile,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await ref.getDownloadURL();

    await _db
        .collection('companies')
        .doc(companyId)
        .collection('employees')
        .doc(userId)
        .update({'photoUrl': url});

    return url;
  }
}
