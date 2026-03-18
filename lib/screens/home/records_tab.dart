import 'package:flutter/material.dart';
import 'package:kintai_app/screens/attendance/attendance_history_screen.dart';
import 'package:kintai_app/screens/home/admin_dashboard_tab.dart';
import 'package:kintai_app/screens/attendance/monthly_summary_screen.dart';

class RecordsTab extends StatelessWidget {
  final bool isAdmin;
  const RecordsTab({super.key, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    if (!isAdmin) {
      return const AttendanceHistoryScreen();
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          bottom: const TabBar(
            tabs: [
              Tab(text: '履歴'),
              Tab(text: '管理'),
              Tab(text: '集計'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AttendanceHistoryScreen(embedded: true),
            AdminDashboardTab(embedded: true),
            MonthlySummaryScreen(embedded: true),
          ],
        ),
      ),
    );
  }
}
