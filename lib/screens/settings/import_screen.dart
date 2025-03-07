import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:kintai_app/providers/company_provider.dart';
import 'package:kintai_app/services/import_service.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  ImportType _selectedType = ImportType.attendance;
  bool _loading = false;
  ImportResult? _result;

  Future<void> _pickAndImport() async {
    final companyId = ref.read(currentUserCompanyProvider).valueOrNull;
    if (companyId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('会社情報が取得できません')));
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final bytes = picked.files.first.bytes;
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ファイルの読み込みに失敗しました')));
      }
      return;
    }

    final csvString = utf8.decode(bytes);
    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final service = ImportService();
      ImportResult result;
      switch (_selectedType) {
        case ImportType.attendance:
          result = await service.importAttendances(companyId, csvString);
        case ImportType.employee:
          result = await service.importEmployees(companyId, csvString);
        case ImportType.location:
          result = await service.importLocations(companyId, csvString);
      }
      setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('インポートエラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copySampleCsv() {
    Clipboard.setData(
        ClipboardData(text: ImportService.sampleCsv(_selectedType)));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('サンプルCSVをコピーしました')));
  }

  String get _typeLabel {
    switch (_selectedType) {
      case ImportType.attendance:
        return '勤怠記録';
      case ImportType.employee:
        return '従業員';
      case ImportType.location:
        return '拠点';
    }
  }

  String get _formatDescription {
    switch (_selectedType) {
      case ImportType.attendance:
        return '列: 名前, 日付(yyyy-MM-dd), 出勤(HH:mm), 退勤(HH:mm), 種別(auto/manual_direct), メモ\n※名前またはメールで従業員を照合します';
      case ImportType.employee:
        return '列: 名前, メール, 権限(admin/member)';
      case ImportType.location:
        return '列: 拠点名, 緯度, 経度, 半径(m)\n※半径省略時は200m';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CSVインポート')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Type selector
            SegmentedButton<ImportType>(
              segments: const [
                ButtonSegment(
                    value: ImportType.attendance,
                    label: Text('勤怠'),
                    icon: Icon(Icons.access_time)),
                ButtonSegment(
                    value: ImportType.employee,
                    label: Text('従業員'),
                    icon: Icon(Icons.people)),
                ButtonSegment(
                    value: ImportType.location,
                    label: Text('拠点'),
                    icon: Icon(Icons.location_on)),
              ],
              selected: {_selectedType},
              onSelectionChanged: (set) =>
                  setState(() {
                    _selectedType = set.first;
                    _result = null;
                  }),
            ),
            const SizedBox(height: 24),

            // Format description
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_typeLabelのCSVフォーマット',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Text(_formatDescription,
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    // Sample CSV preview
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        ImportService.sampleCsv(_selectedType),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _copySampleCsv,
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('サンプルをコピー'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Import button
            FilledButton.icon(
              onPressed: _loading ? null : _pickAndImport,
              icon: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_file),
              label: Text(_loading ? 'インポート中...' : 'CSVファイルを選択してインポート'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56)),
            ),

            // Results
            if (_result != null) ...[
              const SizedBox(height: 24),
              Card(
                color: _result!.errors.isEmpty
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('インポート結果',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Text('成功: ${_result!.success}件'),
                      if (_result!.skipped > 0)
                        Text('スキップ: ${_result!.skipped}件'),
                      if (_result!.errors.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('エラー詳細:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        ...(_result!.errors.length > 10
                                ? _result!.errors.sublist(0, 10)
                                : _result!.errors)
                            .map((e) => Text('  $e',
                                style: const TextStyle(fontSize: 12))),
                        if (_result!.errors.length > 10)
                          Text('  ...他${_result!.errors.length - 10}件',
                              style: const TextStyle(fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
