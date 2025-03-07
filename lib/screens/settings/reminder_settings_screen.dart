import 'package:flutter/material.dart';
import 'package:kintai_app/services/notification_service.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  bool _clockInEnabled = false;
  TimeOfDay _clockInTime = const TimeOfDay(hour: 9, minute: 0);
  bool _clockOutEnabled = false;
  TimeOfDay _clockOutTime = const TimeOfDay(hour: 18, minute: 30);

  @override
  void initState() {
    super.initState();
    NotificationService.init();
  }

  Future<void> _save() async {
    await NotificationService.requestPermissions();

    if (_clockInEnabled) {
      await NotificationService.scheduleClockInReminder(
          _clockInTime.hour, _clockInTime.minute);
    } else {
      await NotificationService.cancelClockIn();
    }

    if (_clockOutEnabled) {
      await NotificationService.scheduleClockOutReminder(
          _clockOutTime.hour, _clockOutTime.minute);
    } else {
      await NotificationService.cancelClockOut();
    }

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('リマインド設定を保存しました')));
      Navigator.pop(context);
    }
  }

  Future<void> _pickTime(bool isClockIn) async {
    final current = isClockIn ? _clockInTime : _clockOutTime;
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null) return;
    setState(() {
      if (isClockIn) {
        _clockInTime = picked;
      } else {
        _clockOutTime = picked;
      }
    });
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('リマインド通知')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('出勤リマインド'),
                    subtitle: const Text('毎日指定時刻に出勤忘れを通知'),
                    value: _clockInEnabled,
                    onChanged: (v) => setState(() => _clockInEnabled = v),
                  ),
                  if (_clockInEnabled)
                    ListTile(
                      title: const Text('通知時刻'),
                      trailing: OutlinedButton(
                        onPressed: () => _pickTime(true),
                        child: Text(_formatTime(_clockInTime)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('退勤リマインド'),
                    subtitle: const Text('毎日指定時刻に退勤忘れを通知'),
                    value: _clockOutEnabled,
                    onChanged: (v) => setState(() => _clockOutEnabled = v),
                  ),
                  if (_clockOutEnabled)
                    ListTile(
                      title: const Text('通知時刻'),
                      trailing: OutlinedButton(
                        onPressed: () => _pickTime(false),
                        child: Text(_formatTime(_clockOutTime)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
