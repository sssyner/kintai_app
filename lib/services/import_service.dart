import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

enum ImportType { attendance, employee, location }

class ImportResult {
  final int success;
  final int skipped;
  final List<String> errors;
  ImportResult({required this.success, required this.skipped, required this.errors});
}

class ImportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Parse CSV string into rows
  List<List<dynamic>> parseCsv(String csvString) {
    return const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(csvString);
  }

  /// Import attendance records from CSV
  /// Expected columns: 名前orメール, 日付(yyyy-MM-dd), 出勤(HH:mm), 退勤(HH:mm), 種別(auto/manual_direct), メモ
  Future<ImportResult> importAttendances(
      String companyId, String csvString) async {
    final rows = parseCsv(csvString);
    if (rows.isEmpty) return ImportResult(success: 0, skipped: 0, errors: ['CSVが空です']);

    // Get employee lookup
    final empSnap = await _db
        .collection('companies')
        .doc(companyId)
        .collection('employees')
        .get();
    final emailToUid = <String, String>{};
    final nameToUid = <String, String>{};
    for (final doc in empSnap.docs) {
      final data = doc.data();
      emailToUid[data['email'] ?? ''] = doc.id;
      nameToUid[data['name'] ?? ''] = doc.id;
    }

    final attRef = _db.collection('companies').doc(companyId).collection('attendances');
    int success = 0;
    int skipped = 0;
    final errors = <String>[];

    // Skip header row if first cell looks like a header
    final startRow = _isHeader(rows.first) ? 1 : 0;

    for (int i = startRow; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 4) {
        skipped++;
        errors.add('行${i + 1}: 列数不足 (${row.length}列)');
        continue;
      }
      try {
        final identifier = row[0].toString().trim();
        final userId = emailToUid[identifier] ?? nameToUid[identifier];
        if (userId == null) {
          skipped++;
          errors.add('行${i + 1}: "$identifier" が従業員に見つかりません');
          continue;
        }

        final dateStr = row[1].toString().trim();
        final clockInStr = row[2].toString().trim();
        final clockOutStr = row[3].toString().trim();
        final type = row.length > 4 ? row[4].toString().trim() : 'auto';
        final memo = row.length > 5 ? row[5].toString().trim() : null;

        final clockInTime = _parseDateTime(dateStr, clockInStr);
        final clockOutTime = clockOutStr.isNotEmpty ? _parseDateTime(dateStr, clockOutStr) : null;

        await attRef.add({
          'userId': userId,
          'locationId': null,
          'locationName': null,
          'clockIn': Timestamp.fromDate(clockInTime),
          'clockOut': clockOutTime != null ? Timestamp.fromDate(clockOutTime) : null,
          'date': dateStr,
          'type': type.isNotEmpty ? type : 'auto',
          'memo': memo?.isNotEmpty == true ? memo : null,
        });
        success++;
      } catch (e) {
        skipped++;
        errors.add('行${i + 1}: $e');
      }
    }
    return ImportResult(success: success, skipped: skipped, errors: errors);
  }

  /// Import employees from CSV
  /// Expected columns: 名前, メール, 権限(admin/member)
  Future<ImportResult> importEmployees(String companyId, String csvString) async {
    final rows = parseCsv(csvString);
    if (rows.isEmpty) return ImportResult(success: 0, skipped: 0, errors: ['CSVが空です']);

    final empRef = _db.collection('companies').doc(companyId).collection('employees');
    int success = 0;
    int skipped = 0;
    final errors = <String>[];

    final startRow = _isHeader(rows.first) ? 1 : 0;

    for (int i = startRow; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 2) {
        skipped++;
        errors.add('行${i + 1}: 列数不足');
        continue;
      }
      try {
        final name = row[0].toString().trim();
        final email = row[1].toString().trim();
        final role = row.length > 2 ? row[2].toString().trim() : 'member';

        if (name.isEmpty || email.isEmpty) {
          skipped++;
          errors.add('行${i + 1}: 名前またはメールが空');
          continue;
        }

        // Use email as doc ID placeholder (actual uid would come from auth)
        // Store as pre-registered employee with a generated ID
        await empRef.add({
          'name': name,
          'email': email,
          'role': (role == 'admin') ? 'admin' : 'member',
          'joinedAt': FieldValue.serverTimestamp(),
        });
        success++;
      } catch (e) {
        skipped++;
        errors.add('行${i + 1}: $e');
      }
    }
    return ImportResult(success: success, skipped: skipped, errors: errors);
  }

  /// Import locations from CSV
  /// Expected columns: 拠点名, 緯度, 経度, 半径(m)
  Future<ImportResult> importLocations(String companyId, String csvString) async {
    final rows = parseCsv(csvString);
    if (rows.isEmpty) return ImportResult(success: 0, skipped: 0, errors: ['CSVが空です']);

    final locRef = _db.collection('companies').doc(companyId).collection('locations');
    int success = 0;
    int skipped = 0;
    final errors = <String>[];

    final startRow = _isHeader(rows.first) ? 1 : 0;

    for (int i = startRow; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) {
        skipped++;
        errors.add('行${i + 1}: 列数不足');
        continue;
      }
      try {
        final name = row[0].toString().trim();
        final lat = double.parse(row[1].toString().trim());
        final lng = double.parse(row[2].toString().trim());
        final radius = row.length > 3 ? double.parse(row[3].toString().trim()) : 200.0;

        if (name.isEmpty) {
          skipped++;
          errors.add('行${i + 1}: 拠点名が空');
          continue;
        }

        await locRef.add({
          'name': name,
          'lat': lat,
          'lng': lng,
          'radius': radius,
          'isActive': true,
        });
        success++;
      } catch (e) {
        skipped++;
        errors.add('行${i + 1}: $e');
      }
    }
    return ImportResult(success: success, skipped: skipped, errors: errors);
  }

  DateTime _parseDateTime(String dateStr, String timeStr) {
    // Support multiple date formats
    final date = DateFormat('yyyy-MM-dd').parse(dateStr);
    final parts = timeStr.split(':');
    return DateTime(
        date.year, date.month, date.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  bool _isHeader(List<dynamic> row) {
    if (row.isEmpty) return false;
    final first = row[0].toString().toLowerCase();
    return first.contains('名前') ||
        first.contains('name') ||
        first.contains('拠点') ||
        first.contains('メール') ||
        first.contains('email');
  }

  /// Generate sample CSV for download reference
  static String sampleCsv(ImportType type) {
    switch (type) {
      case ImportType.attendance:
        return '名前,日付,出勤,退勤,種別,メモ\n田中太郎,2026-03-01,09:00,18:00,auto,\n田中太郎,2026-03-02,08:30,17:30,manual_direct,直行：客先A';
      case ImportType.employee:
        return '名前,メール,権限\n田中太郎,tanaka@example.com,admin\n鈴木花子,suzuki@example.com,member';
      case ImportType.location:
        return '拠点名,緯度,経度,半径\n本社,35.6812,139.7671,200\n大阪支店,34.6937,135.5023,150';
    }
  }
}
