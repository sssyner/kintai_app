import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/services/gps_service.dart';
import 'package:kintai_app/screens/home/employee_home_tab.dart';
import 'package:kintai_app/screens/chat/chat_list_screen.dart';
import 'package:kintai_app/screens/home/records_tab.dart';
import 'package:kintai_app/screens/leaves/leave_list_screen.dart';
import 'package:kintai_app/screens/settings/settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeeAsync = ref.watch(currentEmployeeProvider);

    return employeeAsync.when(
      data: (employee) {
        if (employee == null) {
          return const Scaffold(
              body: Center(child: Text('従業員情報が見つかりません')));
        }
        return _HomeScaffold(isAdmin: employee.isAdmin);
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('エラー: $e'))),
    );
  }
}

class _HomeScaffold extends StatefulWidget {
  final bool isAdmin;
  const _HomeScaffold({required this.isAdmin});

  @override
  State<_HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<_HomeScaffold> with WidgetsBindingObserver {
  int _index = 0;
  bool _permissionRequested = false;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    try {
      // 少し待ってからリクエスト（画面描画後）
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final gps = GpsService();
      await gps.ensureAlwaysPermission();
    } catch (_) {
      // ユーザーが拒否しても続行可能（手動打刻は使える）
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      const EmployeeHomeTab(),
      const ChatListScreen(),
      RecordsTab(isAdmin: widget.isAdmin),
      const LeaveListScreen(),
      const SettingsScreen(),
    ];

    const destinations = <NavigationDestination>[
      NavigationDestination(icon: Icon(Icons.home), label: 'ホーム'),
      NavigationDestination(icon: Icon(Icons.chat), label: 'チャット'),
      NavigationDestination(icon: Icon(Icons.calendar_month), label: '記録'),
      NavigationDestination(icon: Icon(Icons.event_busy), label: '休暇'),
      NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
    ];

    if (_index >= tabs.length) _index = 0;

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: destinations,
      ),
    );
  }
}
