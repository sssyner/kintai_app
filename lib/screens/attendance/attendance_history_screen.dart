import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:kintai_app/providers/auth_provider.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/providers/attendance_provider.dart';
import 'package:kintai_app/providers/leave_provider.dart';
import 'package:kintai_app/models/attendance.dart';
import 'package:kintai_app/models/leave_request.dart';

class AttendanceHistoryScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const AttendanceHistoryScreen({super.key, this.embedded = false});

  @override
  ConsumerState<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState
    extends ConsumerState<AttendanceHistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<String, List<Attendance>> _monthRecords = {};
  Map<String, List<LeaveRequest>> _monthLeaves = {};
  bool _loadingMonth = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMonth());
  }

  Future<void> _loadMonth() async {
    final user = ref.read(authStateProvider).valueOrNull;
    final companyId = ref.read(currentUserCompanyProvider).valueOrNull;
    if (user == null || companyId == null) return;

    setState(() => _loadingMonth = true);
    try {
      final records = await ref
          .read(attendanceServiceProvider)
          .getByMonth(companyId, user.uid, _focusedDay.year, _focusedDay.month);
      final attMap = <String, List<Attendance>>{};
      for (final r in records) {
        attMap.putIfAbsent(r.date, () => []).add(r);
      }

      final leaves = await ref
          .read(leaveServiceProvider)
          .getByMonth(companyId, user.uid, _focusedDay.year, _focusedDay.month);
      final leaveMap = <String, List<LeaveRequest>>{};
      for (final l in leaves) {
        leaveMap.putIfAbsent(l.date, () => []).add(l);
      }

      setState(() {
        _monthRecords = attMap;
        _monthLeaves = leaveMap;
      });
    } finally {
      setState(() => _loadingMonth = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _selectedDay != null
        ? DateFormat('yyyy-MM-dd').format(_selectedDay!)
        : null;
    final dayRecords = dateStr != null ? (_monthRecords[dateStr] ?? []) : [];
    final dayLeaves = dateStr != null ? (_monthLeaves[dateStr] ?? []) : [];
    final timeFormat = DateFormat('HH:mm');

    final body = Column(
      children: [
        TableCalendar(
          firstDay: DateTime(2020),
          lastDay: DateTime(2030),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
          onDaySelected: (selected, focused) {
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            });
          },
          onPageChanged: (focused) {
            _focusedDay = focused;
            _loadMonth();
          },
          eventLoader: (day) {
            final key = DateFormat('yyyy-MM-dd').format(day);
            return [
              ...(_monthRecords[key] ?? []),
              ...(_monthLeaves[key] ?? []),
            ];
          },
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, date, events) {
              final key = DateFormat('yyyy-MM-dd').format(date);
              final hasAtt = (_monthRecords[key] ?? []).isNotEmpty;
              final hasLeave = (_monthLeaves[key] ?? []).isNotEmpty;
              if (!hasAtt && !hasLeave) return null;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasAtt)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (hasLeave)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              );
            },
          ),
          headerStyle: const HeaderStyle(formatButtonVisible: false),
          locale: 'ja_JP',
        ),
        const Divider(),
        if (_loadingMonth)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_loadingMonth && dayRecords.isEmpty && dayLeaves.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('この日の記録はありません'),
          ),
        // 休暇
        ...dayLeaves.map((l) => ListTile(
              leading: Icon(Icons.event_busy, color: Colors.orange.shade700),
              title: Text(l.typeLabel),
              subtitle: Text(l.statusLabel),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: l.status == 'approved'
                      ? Colors.green.withValues(alpha: 0.15)
                      : l.status == 'rejected'
                          ? Colors.red.withValues(alpha: 0.15)
                          : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(l.statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: l.status == 'approved'
                          ? Colors.green
                          : l.status == 'rejected'
                              ? Colors.red
                              : Colors.orange,
                    )),
              ),
            )),
        // 出退勤
        ...dayRecords.map((att) => ListTile(
              leading: Icon(
                att.type == 'manual_direct'
                    ? Icons.directions_walk
                    : att.type == 'auto_geofence'
                        ? Icons.location_on
                        : Icons.gps_fixed,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                '出勤: ${timeFormat.format(att.clockIn)}'
                '${att.clockOut != null ? '  退勤: ${timeFormat.format(att.clockOut!)}' : '  (勤務中)'}',
              ),
              subtitle: Text([
                if (att.locationName != null) '拠点: ${att.locationName}',
                if (att.type == 'manual_direct') '直行直帰',
                if (att.type == 'auto_geofence') '自動打刻',
                if (att.memo != null && att.memo!.isNotEmpty) 'メモ: ${att.memo}',
              ].join(' / ')),
            )),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(),
      body: body,
    );
  }
}
