import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:kintai_app/models/attendance.dart';
import 'package:kintai_app/providers/company_provider.dart';

class AttendanceEditScreen extends ConsumerStatefulWidget {
  final Attendance attendance;
  const AttendanceEditScreen({super.key, required this.attendance});

  @override
  ConsumerState<AttendanceEditScreen> createState() =>
      _AttendanceEditScreenState();
}

class _AttendanceEditScreenState extends ConsumerState<AttendanceEditScreen> {
  late DateTime _clockIn;
  late DateTime? _clockOut;
  late TextEditingController _memoController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _clockIn = widget.attendance.clockIn;
    _clockOut = widget.attendance.clockOut;
    _memoController = TextEditingController(text: widget.attendance.memo ?? '');
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isClockIn) async {
    final current = isClockIn ? _clockIn : (_clockOut ?? DateTime.now());
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    setState(() {
      final dt = DateTime(
          current.year, current.month, current.day, time.hour, time.minute);
      if (isClockIn) {
        _clockIn = dt;
      } else {
        _clockOut = dt;
      }
    });
  }

  Future<void> _pickDate(bool isClockIn) async {
    final current = isClockIn ? _clockIn : (_clockOut ?? DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date == null) return;
    setState(() {
      final dt =
          DateTime(date.year, date.month, date.day, current.hour, current.minute);
      if (isClockIn) {
        _clockIn = dt;
      } else {
        _clockOut = dt;
      }
    });
  }

  Future<void> _save() async {
    final companyId = ref.read(currentUserCompanyProvider).valueOrNull;
    if (companyId == null) return;

    setState(() => _loading = true);
    try {
      final data = <String, dynamic>{
        'clockIn': Timestamp.fromDate(_clockIn),
        'date': DateFormat('yyyy-MM-dd').format(_clockIn),
        'memo': _memoController.text.isNotEmpty ? _memoController.text : null,
      };
      if (_clockOut != null) {
        data['clockOut'] = Timestamp.fromDate(_clockOut!);
      }

      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('attendances')
          .doc(widget.attendance.id)
          .update(data);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('打刻記録を削除'),
        content: const Text('この記録を完全に削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('削除')),
        ],
      ),
    );
    if (confirm != true) return;

    final companyId = ref.read(currentUserCompanyProvider).valueOrNull;
    if (companyId == null) return;

    await FirebaseFirestore.instance
        .collection('companies')
        .doc(companyId)
        .collection('attendances')
        .doc(widget.attendance.id)
        .delete();

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd');
    final timeFormat = DateFormat('HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('打刻修正'),
        actions: [
          IconButton(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline, color: Colors.red),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Clock in
            Text('出勤', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(true),
                    child: Text(dateFormat.format(_clockIn)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(true),
                    child: Text(timeFormat.format(_clockIn)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Clock out
            Text('退勤', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_clockOut != null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(false),
                      child: Text(dateFormat.format(_clockOut!)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(false),
                      child: Text(timeFormat.format(_clockOut!)),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _clockOut = null),
                    icon: const Icon(Icons.clear),
                  ),
                ],
              )
            else
              OutlinedButton(
                onPressed: () {
                  setState(() => _clockOut = DateTime.now());
                },
                child: const Text('退勤時刻を追加'),
              ),
            const SizedBox(height: 24),

            // Memo
            TextField(
              controller: _memoController,
              decoration: const InputDecoration(labelText: 'メモ'),
              maxLines: 3,
            ),
            const SizedBox(height: 8),

            // Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '種別: ${widget.attendance.type == 'manual_direct' ? '直行直帰' : 'GPS'}'),
                    if (widget.attendance.locationName != null)
                      Text('拠点: ${widget.attendance.locationName}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
