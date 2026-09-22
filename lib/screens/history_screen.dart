import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/money.dart';
import '../services/history_store.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    // Load after the first frame so the screen can paint immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.history;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan history'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _confirmClear(context),
            ),
        ],
      ),
      body: history.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _HistoryTile(record: history[index]),
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear scan history?'),
        content: const Text(
            'This permanently deletes every saved scan on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.alert),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<AppState>().clearHistory();
    }
  }
}

class _HistoryTile extends StatelessWidget {
  final ScanRecord record;

  const _HistoryTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final flagCount = record.report.flags.length;
    final clean = flagCount == 0;
    final color = clean ? AppColors.success : AppColors.alert;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        context.read<AppState>().showRecord(record);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ResultScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                clean ? Icons.verified_rounded : Icons.report_problem_rounded,
                color: color,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clean
                        ? 'No issues'
                        : '$flagCount ${flagCount == 1 ? 'issue' : 'issues'} found',
                    style: const TextStyle(
                        fontSize: 16.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_formatDate(record.scannedAt)} · '
                    '${_sourceLabel(record.bill.source)}'
                    '${record.bill.total.isFound ? ' · ${formatRupees(record.bill.total.value)}' : ''}',
                    style: const TextStyle(
                        fontSize: 13.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  String _sourceLabel(String source) => switch (source) {
        'camera' => 'Camera',
        'gallery' => 'Gallery',
        'demo' => 'Demo',
        _ => 'Scan',
      };

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded,
                  size: 58, color: AppColors.textSecondary),
              SizedBox(height: 16),
              Text('No scans yet',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text(
                'Scanned bills are saved here on this device so you can show '
                'them again later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15, height: 1.4, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
}
