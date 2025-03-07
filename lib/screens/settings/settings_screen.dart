import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kintai_app/providers/auth_provider.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/providers/location_provider.dart';
import 'package:kintai_app/screens/settings/import_screen.dart';
import 'package:kintai_app/screens/settings/export_screen.dart';
import 'package:kintai_app/screens/settings/reminder_settings_screen.dart';
import 'package:kintai_app/screens/locations/location_list_screen.dart';
import 'package:kintai_app/screens/employees/employee_list_screen.dart';
import 'package:kintai_app/services/native_geofence_service.dart';
import 'package:kintai_app/services/mock_data_service.dart';
import 'package:kintai_app/widgets/employee_avatar.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _autoGeofenceEnabled = false;
  bool _geofenceLoading = false;
  bool _uploadingPhoto = false;
  final _geofenceService = NativeGeofenceService();

  @override
  void initState() {
    super.initState();
    _loadGeofenceSetting();
  }

  Future<void> _loadGeofenceSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoGeofenceEnabled = prefs.getBool('auto_geofence_enabled') ?? true;
      });
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final user = ref.read(authStateProvider).valueOrNull;
    final companyId = ref.read(currentUserCompanyProvider).valueOrNull;
    if (user == null || companyId == null) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('ライブラリから選択'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final service = ref.read(profileImageServiceProvider);
      final xFile = await service.pickImage(source: source);
      if (xFile == null) {
        if (mounted) setState(() => _uploadingPhoto = false);
        return;
      }

      await service.uploadAndSave(
        companyId: companyId,
        userId: user.uid,
        imageFile: File(xFile.path),
      );

      // Refresh employee data
      ref.invalidate(currentEmployeeProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('プロフィール画像を更新しました')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _showWorkHoursDialog(String companyId, int currentMinutes) async {
    int hours = currentMinutes ~/ 60;
    int mins = currentMinutes % 60;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('標準勤務時間'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: hours,
                      decoration: const InputDecoration(labelText: '時間'),
                      items: List.generate(16, (i) => i + 1)
                          .map((h) => DropdownMenuItem(value: h, child: Text('$h')))
                          .toList(),
                      onChanged: (v) => setDialogState(() => hours = v ?? hours),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: mins,
                      decoration: const InputDecoration(labelText: '分'),
                      items: [0, 15, 30, 45]
                          .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                          .toList(),
                      onChanged: (v) => setDialogState(() => mins = v ?? mins),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, hours * 60 + mins),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .update({'standardWorkMinutes': result});
      ref.invalidate(companyProvider(companyId));
    }
  }

  Future<void> _showOvertimeThresholdDialog(String companyId, double currentHours) async {
    double value = currentHours;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('残業アラート閾値'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.toInt()}時間／月', style: Theme.of(context).textTheme.headlineSmall),
              Slider(
                value: value,
                min: 10,
                max: 80,
                divisions: 14,
                label: '${value.toInt()}h',
                onChanged: (v) => setDialogState(() => value = v),
              ),
              const Text('この閾値の80%を超えると警告表示', style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, value),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .update({'overtimeThresholdHours': result});
      ref.invalidate(companyProvider(companyId));
    }
  }

  Future<void> _toggleAutoGeofence(bool enabled) async {
    setState(() => _geofenceLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = ref.read(authStateProvider).valueOrNull;
      final companyId = ref.read(currentUserCompanyProvider).valueOrNull;

      if (enabled && user != null && companyId != null) {
        await _geofenceService.setUserInfo(
          companyId: companyId,
          userId: user.uid,
        );

        final locations =
            ref.read(locationsProvider(companyId)).valueOrNull ?? [];
        final activeLocations = locations.where((l) => l.isActive).toList();

        if (activeLocations.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('有効な拠点がありません。先に拠点を登録してください。')),
            );
          }
          setState(() => _geofenceLoading = false);
          return;
        }

        final geofenceData = activeLocations
            .map((l) => {
                  'id': l.id,
                  'lat': l.lat,
                  'lng': l.lng,
                  'radius': l.radius,
                  'name': l.name,
                })
            .toList();

        final success = await _geofenceService.registerGeofences(geofenceData);
        if (!success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ジオフェンスの登録に失敗しました。位置情報の権限を確認してください。')),
            );
          }
          setState(() => _geofenceLoading = false);
          return;
        }
      } else {
        await _geofenceService.unregisterAll();
      }

      await prefs.setBool('auto_geofence_enabled', enabled);
      setState(() => _autoGeofenceEnabled = enabled);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? '自動打刻を有効にしました' : '自動打刻を無効にしました'),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _geofenceLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final companyId = ref.watch(currentUserCompanyProvider).valueOrNull;
    final employee = ref.watch(currentEmployeeProvider).valueOrNull;
    final companyAsync =
        companyId != null ? ref.watch(companyProvider(companyId)) : null;

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        children: [
          // Profile with photo
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
              child: Stack(
                children: [
                  EmployeeAvatar(
                    employee: employee,
                    name: employee?.name ?? user?.displayName,
                    radius: 48,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: _uploadingPhoto
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.camera_alt,
                              size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              employee?.name ?? user?.displayName ?? '',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Center(
            child: Text(
              user?.email ?? '',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),

          // Company info
          if (companyAsync != null)
            companyAsync.when(
              data: (company) => ListTile(
                leading: const Icon(Icons.business),
                title: const Text('会社'),
                subtitle: Text(company.name),
              ),
              loading: () => const ListTile(
                leading: Icon(Icons.business),
                title: Text('読み込み中...'),
              ),
              error: (_, _) => const SizedBox.shrink(),
            ),

          if (employee != null)
            ListTile(
              leading: const Icon(Icons.badge),
              title: const Text('権限'),
              subtitle: Text(employee.isAdmin ? '管理者' : 'メンバー'),
            ),
          const Divider(),

          // Auto geofence toggle
          SwitchListTile(
            secondary: const Icon(Icons.location_on),
            title: const Text('自動打刻（ジオフェンス）'),
            subtitle: Text(
              _autoGeofenceEnabled
                  ? 'オフィスの到着・退出で自動打刻'
                  : 'オフにすると手動打刻のみ',
            ),
            value: _autoGeofenceEnabled,
            onChanged: _geofenceLoading ? null : _toggleAutoGeofence,
          ),

          // Work hours settings (admin only)
          if (employee != null && employee.isAdmin && companyAsync != null)
            companyAsync.when(
              data: (company) => Column(
                children: [
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('標準勤務時間'),
                    subtitle: Text('${company.standardWorkMinutes ~/ 60}時間${company.standardWorkMinutes % 60 > 0 ? '${company.standardWorkMinutes % 60}分' : ''}／日'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showWorkHoursDialog(companyId!, company.standardWorkMinutes),
                  ),
                  ListTile(
                    leading: const Icon(Icons.warning_amber),
                    title: const Text('残業アラート閾値'),
                    subtitle: Text('${company.overtimeThresholdHours.toInt()}時間／月'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showOvertimeThresholdDialog(companyId!, company.overtimeThresholdHours),
                  ),
                ],
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),

          // Admin: locations & employees
          if (employee != null && employee.isAdmin) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('拠点管理'),
              subtitle: const Text('オフィス拠点の追加・編集'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const LocationListScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('従業員管理'),
              subtitle: const Text('従業員の一覧・権限管理'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const EmployeeListScreen()),
              ),
            ),
          ],

          // Import/Export (admin only)
          if (employee != null && employee.isAdmin) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('CSVインポート'),
              subtitle: const Text('勤怠記録・従業員・拠点を一括取り込み'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ImportScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('CSVエクスポート'),
              subtitle: const Text('勤怠記録・従業員・拠点を出力'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExportScreen()),
              ),
            ),
          ],
          const Divider(),

          // Reminder settings
          ListTile(
            leading: const Icon(Icons.notifications_active),
            title: const Text('リマインド通知'),
            subtitle: const Text('打刻忘れ防止の通知設定'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ReminderSettingsScreen()),
            ),
          ),
          const Divider(),

          // Legal links
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('利用規約'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(
              Uri.parse('https://company.synergyhq.jp/kintai/terms'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: const Text('プライバシーポリシー'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(
              Uri.parse('https://company.synergyhq.jp/kintai/privacy'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const Divider(),

          // Logout
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('ログアウト', style: TextStyle(color: Colors.red)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('ログアウト'),
                  content: const Text('ログアウトしますか？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('キャンセル')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('ログアウト')),
                  ],
                ),
              );
              if (confirm == true) {
                if (_autoGeofenceEnabled) {
                  await _geofenceService.unregisterAll();
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('auto_geofence_enabled', false);
                }
                if (context.mounted) {
                  await ref.read(authServiceProvider).signOut();
                }
              }
            },
          ),
          const Divider(),

          // デモデータ投入
          if (employee != null && employee.isAdmin && companyId != null)
            ListTile(
              leading: const Icon(Icons.science, color: Colors.purple),
              title: const Text('デモデータ投入', style: TextStyle(color: Colors.purple)),
              subtitle: const Text('スクショ用のモックデータを追加'),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('デモデータ投入'),
                    content: const Text('従業員4名・1ヶ月分の出退勤・休暇・チャットデータを追加します。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('キャンセル')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('投入')),
                    ],
                  ),
                );
                if (confirm == true) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('デモデータ投入中...')),
                    );
                  }
                  try {
                    await MockDataService().seedDemoData(companyId, user!.uid);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('デモデータを投入しました')),
                      );
                    }
                  } on Exception catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('エラー: $e')),
                      );
                    }
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}
