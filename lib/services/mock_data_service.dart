import 'package:cloud_firestore/cloud_firestore.dart';

class MockDataService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> seedDemoData(String companyId, String adminUserId) async {
    // デモ従業員（既存のadminに加えて4人追加）
    final demoEmployees = [
      {'id': 'demo_tanaka', 'name': '田中 太郎', 'email': 'tanaka@example.com', 'role': 'member'},
      {'id': 'demo_suzuki', 'name': '鈴木 花子', 'email': 'suzuki@example.com', 'role': 'member'},
      {'id': 'demo_yamamoto', 'name': '山本 健太', 'email': 'yamamoto@example.com', 'role': 'member'},
      {'id': 'demo_sato', 'name': '佐藤 美咲', 'email': 'sato@example.com', 'role': 'admin'},
    ];

    final empRef = _db.collection('companies').doc(companyId).collection('employees');
    final attRef = _db.collection('companies').doc(companyId).collection('attendances');
    final leaveRef = _db.collection('companies').doc(companyId).collection('leaves');
    final chatRef = _db.collection('companies').doc(companyId).collection('chatRooms');

    // 既存データ削除
    await _deleteCollection(attRef);
    await _deleteCollection(leaveRef);
    final existingRooms = await chatRef.get();
    for (final room in existingRooms.docs) {
      await _deleteCollection(room.reference.collection('messages'));
      await room.reference.delete();
    }
    for (final emp in demoEmployees) {
      await empRef.doc(emp['id'] as String).delete();
    }

    // admin名をデモ用に上書き
    const adminDemoName = '中村 颯太';
    await empRef.doc(adminUserId).update({'name': adminDemoName});

    // 従業員追加
    for (final emp in demoEmployees) {
      await empRef.doc(emp['id'] as String).set({
        'name': emp['name'],
        'email': emp['email'],
        'role': emp['role'],
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }

    final allUserIds = [adminUserId, ...demoEmployees.map((e) => e['id'] as String)];

    // 1ヶ月分の出退勤データ（2026年3月）
    final now = DateTime.now();
    final year = now.year;
    final month = now.month;

    for (int day = 1; day <= now.day; day++) {
      final date = DateTime(year, month, day);
      if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) continue;
      final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

      for (final userId in allUserIds) {
        // 一部ランダムに休みにする
        if (_shouldSkip(userId, day)) continue;

        final clockInHour = 8 + (day % 3 == 0 ? 1 : 0); // 8時 or 9時出勤
        final clockInMin = (day * 7 + userId.hashCode.abs()) % 30; // 0〜29分
        final workHours = 8 + (day % 5 == 0 ? 1 : 0) + (day % 7 == 0 ? 1 : 0); // 8〜10時間
        final clockOutMin = (day * 13 + userId.hashCode.abs()) % 45;

        final clockIn = DateTime(year, month, day, clockInHour, clockInMin);
        final isToday = day == now.day;
        final clockOut = isToday ? null : DateTime(year, month, day, clockInHour + workHours, clockOutMin);

        final type = day % 10 == 0 ? 'manual_direct' : (day % 6 == 0 ? 'auto_geofence' : 'auto');

        await attRef.add({
          'userId': userId,
          'locationId': type == 'manual_direct' ? null : 'office_1',
          'locationName': type == 'manual_direct' ? null : '本社オフィス',
          'clockIn': Timestamp.fromDate(clockIn),
          'clockOut': clockOut != null ? Timestamp.fromDate(clockOut) : null,
          'date': dateStr,
          'type': type,
          'memo': type == 'manual_direct' ? '客先訪問' : null,
        });
      }
    }

    // 休暇データ
    final leaveData = [
      {'userId': 'demo_tanaka', 'userName': '田中 太郎', 'type': 'paid', 'date': '$year-${month.toString().padLeft(2, '0')}-05', 'status': 'approved', 'reason': '家族の用事'},
      {'userId': 'demo_suzuki', 'userName': '鈴木 花子', 'type': 'sick', 'date': '$year-${month.toString().padLeft(2, '0')}-07', 'status': 'approved', 'reason': '体調不良'},
      {'userId': 'demo_yamamoto', 'userName': '山本 健太', 'type': 'half_am', 'date': '$year-${month.toString().padLeft(2, '0')}-10', 'status': 'approved', 'reason': '通院'},
      {'userId': 'demo_sato', 'userName': '佐藤 美咲', 'type': 'paid', 'date': '$year-${month.toString().padLeft(2, '0')}-12', 'status': 'approved', 'reason': null},
      {'userId': adminUserId, 'userName': adminDemoName, 'type': 'paid', 'date': '$year-${month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}', 'status': 'approved', 'reason': null},
      {'userId': 'demo_tanaka', 'userName': '田中 太郎', 'type': 'paid', 'date': '$year-${month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}', 'status': 'pending', 'reason': '私用'},
    ];

    for (final l in leaveData) {
      await leaveRef.add({
        ...l,
        'reviewedBy': l['status'] == 'approved' ? adminUserId : null,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // チャットデータ - 全体チャットルームを取得
    final companyRoomSnap = await chatRef.where('type', isEqualTo: 'company').limit(1).get();
    String companyRoomId;
    if (companyRoomSnap.docs.isNotEmpty) {
      companyRoomId = companyRoomSnap.docs.first.id;
    } else {
      final ref = chatRef.doc();
      await ref.set({
        'type': 'company',
        'name': '全体チャット',
        'memberIds': [],
        'createdAt': FieldValue.serverTimestamp(),
      });
      companyRoomId = ref.id;
    }

    // リアルなチャットメッセージ（絶対時間で朝から）
    final today = DateTime(year, month, now.day);
    final chatMessages = [
      {'senderId': 'demo_sato', 'senderName': '佐藤 美咲', 'text': 'おはようございます！', 'hour': 8, 'min': 32},
      {'senderId': 'demo_tanaka', 'senderName': '田中 太郎', 'text': 'おはようございます', 'hour': 8, 'min': 35},
      {'senderId': adminUserId, 'senderName': adminDemoName, 'text': 'おはよう', 'hour': 8, 'min': 41},
      {'senderId': 'demo_suzuki', 'senderName': '鈴木 花子', 'text': 'おはようございます〜', 'hour': 8, 'min': 48},
      {'senderId': 'demo_sato', 'senderName': '佐藤 美咲', 'text': '今日の15時から会議室Bで定例ミーティングあります。資料は共有フォルダにアップ済みです', 'hour': 10, 'min': 15},
      {'senderId': 'demo_tanaka', 'senderName': '田中 太郎', 'text': '了解です！', 'hour': 10, 'min': 22},
      {'senderId': 'demo_yamamoto', 'senderName': '山本 健太', 'text': '承知しました。今外出中なので15時に戻ります', 'hour': 10, 'min': 30},
      {'senderId': adminUserId, 'senderName': adminDemoName, 'text': '山本さん、先方との打ち合わせどうでした？', 'hour': 13, 'min': 5},
      {'senderId': 'demo_yamamoto', 'senderName': '山本 健太', 'text': '先方到着しました。新規案件の件、前向きに検討いただけそうです', 'hour': 13, 'min': 12},
      {'senderId': adminUserId, 'senderName': adminDemoName, 'text': 'いいね。詳細は戻ってから聞かせて', 'hour': 13, 'min': 15},
      {'senderId': 'demo_yamamoto', 'senderName': '山本 健太', 'text': 'はい！', 'hour': 13, 'min': 16},
      {'senderId': 'demo_suzuki', 'senderName': '鈴木 花子', 'text': '経費精算の締め切り明日までなので忘れずにお願いします🙏', 'hour': 15, 'min': 40},
      {'senderId': 'demo_tanaka', 'senderName': '田中 太郎', 'text': 'あ、やばい。今日中に出します', 'hour': 15, 'min': 47},
      {'senderId': 'demo_sato', 'senderName': '佐藤 美咲', 'text': '私も出しますー', 'hour': 15, 'min': 52},
      {'senderId': adminUserId, 'senderName': adminDemoName, 'text': '了解、みんなよろしく', 'hour': 16, 'min': 3},
    ];

    final msgRef = chatRef.doc(companyRoomId).collection('messages');
    for (final msg in chatMessages) {
      final time = DateTime(year, month, now.day, msg['hour'] as int, msg['min'] as int);
      await msgRef.add({
        'senderId': msg['senderId'],
        'senderName': msg['senderName'],
        'text': msg['text'],
        'createdAt': Timestamp.fromDate(time),
      });
    }

    // 最後のメッセージでルーム更新
    await chatRef.doc(companyRoomId).update({
      'lastMessage': '了解、みんなよろしく',
      'lastMessageAt': Timestamp.fromDate(DateTime(year, month, now.day, 16, 3)),
      'lastMessageBy': adminDemoName,
    });

    // グループチャット作成
    final groupRef = chatRef.doc();
    await groupRef.set({
      'type': 'group',
      'name': '営業チーム',
      'memberIds': [adminUserId, 'demo_tanaka', 'demo_yamamoto'],
      'lastMessage': '来週の訪問スケジュール送ります',
      'lastMessageAt': Timestamp.fromDate(DateTime(year, month, now.day, 14, 20)),
      'lastMessageBy': '田中 太郎',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final groupMsgRef = groupRef.collection('messages');
    final groupMessages = [
      {'senderId': adminUserId, 'senderName': adminDemoName, 'text': 'A社の見積もり、今週中に出せる？', 'hour': 9, 'min': 10},
      {'senderId': 'demo_tanaka', 'senderName': '田中 太郎', 'text': '明日中には出せます', 'hour': 9, 'min': 18},
      {'senderId': 'demo_yamamoto', 'senderName': '山本 健太', 'text': '自分のB社分も明日出します', 'hour': 9, 'min': 25},
      {'senderId': adminUserId, 'senderName': adminDemoName, 'text': 'よろしく。あとC社のフォローもお願い', 'hour': 9, 'min': 30},
      {'senderId': 'demo_tanaka', 'senderName': '田中 太郎', 'text': 'C社は来週訪問予定です', 'hour': 9, 'min': 38},
      {'senderId': 'demo_tanaka', 'senderName': '田中 太郎', 'text': '来週の訪問スケジュール送ります', 'hour': 14, 'min': 20},
    ];

    for (final msg in groupMessages) {
      final time = DateTime(year, month, now.day, msg['hour'] as int, msg['min'] as int);
      await groupMsgRef.add({
        'senderId': msg['senderId'],
        'senderName': msg['senderName'],
        'text': msg['text'],
        'createdAt': Timestamp.fromDate(time),
      });
    }
  }

  bool _shouldSkip(String userId, int day) {
    if (userId == 'demo_tanaka' && day == 5) return true;
    if (userId == 'demo_suzuki' && day == 7) return true;
    if (userId == 'demo_sato' && day == 12) return true;
    return false;
  }

  Future<void> _deleteCollection(CollectionReference ref) async {
    final snap = await ref.get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }
}
