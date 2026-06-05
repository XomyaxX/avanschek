import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/db_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Future<List<Map<String, dynamic>>>? _reportsFuture;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  void _loadReports() {
    setState(() {
      _reportsFuture = DbService.getReports();
    });
  }

  Future<void> _deleteReport(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить отчёт?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DbService.deleteReport(id);
      _loadReports();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🗑️ Отчёт удалён')),
        );
      }
    }
  }

  void _showReportDetails(Map<String, dynamic> report) async {
    final checks = await DbService.getChecksForReport(report['id'] as int);
    if (!mounted) return;

    final dateStr = report['created_at'] != null
        ? DateFormat('dd.MM.yyyy HH:mm').format(
            DateTime.parse(report['created_at'] as String))
        : '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Детали отчёта'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('ФИО', report['fio'] ?? ''),
              _detailRow('Дата отчёта', report['report_date'] ?? ''),
              _detailRow('Создан', dateStr),
              _detailRow(
                'Получено аванса',
                '${(report['advance_received'] as num?)?.toStringAsFixed(2) ?? '0.00'} ₽',
              ),
              _detailRow(
                'Итого по чекам',
                '${(report['total_amount'] as num?)?.toStringAsFixed(2) ?? '0.00'} ₽',
              ),
              _detailRow('Чеков', '${checks.length}'),
              const SizedBox(height: 12),
              const Text(
                'Чеки:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...checks.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${c['name'] ?? ''} — ${(c['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'} ₽',
                      style: const TextStyle(fontSize: 13),
                    ),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История отчётов'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _reportsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final reports = snapshot.data ?? [];

          if (reports.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    'Нет сохранённых отчётов',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              final dateStr = report['created_at'] != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(
                      DateTime.parse(report['created_at'] as String))
                  : '';
              final total = (report['total_amount'] as num?)?.toStringAsFixed(2) ?? '0.00';

              return Dismissible(
                key: ValueKey('report_${report['id']}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) async {
                  await _deleteReport(report['id'] as int);
                  return false; // Удаление управляется внутри _deleteReport
                },
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    title: Text(
                      report['fio'] ?? 'Без имени',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(dateStr),
                        Text('Итого: $total ₽'),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteReport(report['id'] as int),
                    ),
                    onTap: () => _showReportDetails(report),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
