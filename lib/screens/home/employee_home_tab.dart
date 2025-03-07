import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kintai_app/providers/auth_provider.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/providers/attendance_provider.dart';
import 'package:kintai_app/providers/location_provider.dart';
import 'package:kintai_app/providers/gps_provider.dart';
import 'package:kintai_app/models/attendance.dart';
import 'package:kintai_app/services/native_geofence_service.dart';

class EmployeeHomeTab extends ConsumerWidget {
  const EmployeeHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final companyId = ref.watch(currentUserCompanyProvider).valueOrNull;

    if (user == null || companyId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final todayAsync = ref.watch(
        todayAttendanceProvider((companyId: companyId, userId: user.uid)));

    return Scaffold(
      appBar: AppBar(),
      body: todayAsync.when(
        data: (attendance) => _HomeBody(
          companyId: companyId,
          userId: user.uid,
          attendance: attendance,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
      ),
    );
  }
}

class _HomeBody extends ConsumerStatefulWidget {
  final String companyId;
  final String userId;
  final Attendance? attendance;

  const _HomeBody({
    required this.companyId,
    required this.userId,
    required this.attendance,
  });

  @override
  ConsumerState<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends ConsumerState<_HomeBody> {
  bool _loading = false;
  bool _autoGeofenceEnabled = false;
  final _geofenceService = NativeGeofenceService();
  StreamSubscription<Map<String, dynamic>>? _geofenceEventSub;

  @override
  void initState() {
    super.initState();
    _loadGeofenceStatus();
    _listenGeofenceEvents();
  }

  @override
  void dispose() {
    _geofenceEventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadGeofenceStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoGeofenceEnabled = prefs.getBool('auto_geofence_enabled') ?? true;
      });
    }
  }

  void _listenGeofenceEvents() {
    _geofenceEventSub = _geofenceService.events.listen((event) {
      final eventType = event['event'] as String?;
      if (eventType == null) return;

      // Riverpodのストリームが自動的にFirestoreの変更を拾うので、
      // ここではSnackBarで通知するだけ
      if (mounted) {
        final message = eventType == 'enter' ? '自動出勤を検知しました' : '自動退勤を検知しました';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    });
  }

  Future<void> _clockInGps() async {
    setState(() => _loading = true);
    try {
      final position = await ref.read(gpsServiceProvider).getCurrentPosition();
      final locations =
          ref.read(locationsProvider(widget.companyId)).valueOrNull ?? [];
      final gps = ref.read(gpsServiceProvider);
      final nearest =
          gps.findNearestGeofence(position.latitude, position.longitude, locations);
      final isInside = nearest != null &&
          gps.isInsideGeofence(
              position.latitude, position.longitude, nearest);

      await ref.read(attendanceServiceProvider).clockIn(
            companyId: widget.companyId,
            userId: widget.userId,
            locationId: isInside ? nearest.id : null,
            locationName: isInside ? nearest.name : null,
            type: 'auto',
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(isInside
                  ? '${nearest.name}で出勤しました'
                  : '出勤しました（拠点外）')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clockOutGps() async {
    if (widget.attendance == null) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(attendanceServiceProvider)
          .clockOut(widget.companyId, widget.attendance!.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('退勤しました')));
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _directClockIn() async {
    final memo = await _showMemoDialog('直行 - 行き先を入力');
    if (memo == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(attendanceServiceProvider).clockIn(
            companyId: widget.companyId,
            userId: widget.userId,
            type: 'manual_direct',
            memo: memo,
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('直行で出勤しました')));
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _directClockOut() async {
    if (widget.attendance == null) return;
    final memo = await _showMemoDialog('直帰 - メモを入力');
    if (memo == null) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(attendanceServiceProvider)
          .clockOut(widget.companyId, widget.attendance!.id, memo: memo);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('直帰で退勤しました')));
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _showMemoDialog(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'メモ（任意）'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.attendance;
    final isClockedIn = att != null && !att.isClockedOut;
    final isDone = att != null && att.isClockedOut;
    final timeFormat = DateFormat('HH:mm');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Auto geofence status banner
          if (_autoGeofenceEnabled)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.location_on,
                        color: Theme.of(context).colorScheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '自動打刻ON — オフィスの到着・退出で自動記録',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_autoGeofenceEnabled) const SizedBox(height: 12),

          // Status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    isDone
                        ? Icons.check_circle
                        : isClockedIn
                            ? Icons.work
                            : Icons.access_time,
                    size: 48,
                    color: isDone
                        ? Colors.green
                        : isClockedIn
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isDone
                        ? '退勤済み'
                        : isClockedIn
                            ? '出勤中'
                            : '未出勤',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (att != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '出勤: ${timeFormat.format(att.clockIn)}'
                      '${att.clockOut != null ? '  退勤: ${timeFormat.format(att.clockOut!)}' : ''}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (att.locationName != null)
                      Text('拠点: ${att.locationName}',
                          style: Theme.of(context).textTheme.bodyMedium),
                    if (att.type == 'manual_direct')
                      Text('種別: 直行直帰',
                          style: Theme.of(context).textTheme.bodyMedium),
                    if (att.type == 'auto_geofence')
                      Text('種別: 自動打刻',
                          style: Theme.of(context).textTheme.bodyMedium),
                    if (att.memo != null && att.memo!.isNotEmpty)
                      Text('メモ: ${att.memo}',
                          style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Buttons
          if (!isClockedIn && !isDone) ...[
            FilledButton.icon(
              onPressed: _loading ? null : _clockInGps,
              icon: const Icon(Icons.gps_fixed),
              label: const Text('出勤（GPS）'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _directClockIn,
              icon: const Icon(Icons.directions_walk),
              label: const Text('直行 - 業務開始'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56)),
            ),
          ],
          if (isClockedIn) ...[
            FilledButton.icon(
              onPressed: _loading ? null : _clockOutGps,
              icon: const Icon(Icons.gps_fixed),
              label: const Text('退勤（GPS）'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _directClockOut,
              icon: const Icon(Icons.directions_walk),
              label: const Text('直帰 - 業務終了'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56)),
            ),
          ],
          if (_loading) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
