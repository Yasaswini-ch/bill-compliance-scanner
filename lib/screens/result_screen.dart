import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/compliance_flag.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/bill_summary_card.dart';
import '../widgets/flag_card.dart';
import '../widgets/notes_card.dart';
import '../widgets/verdict_header.dart';

/// The screen the jury looks at. Verdict first and large, then the
/// violations, then the evidence the verdict was built from.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final report = state.report;
    final bill = state.bill;

    if (report == null || bill == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Result')),
        body: const Center(child: Text('Nothing scanned yet.')),
      );
    }

    final highFirst = [
      ...report.flags.where((f) => f.severity == FlagSeverity.high),
      ...report.flags.where((f) => f.severity == FlagSeverity.medium),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan result'),
        actions: [
          if (bill.rawText.isNotEmpty)
            IconButton(
              tooltip: 'Show raw scanned text',
              icon: const Icon(Icons.text_snippet_outlined),
              onPressed: () => _showRawText(context, bill.rawText),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            VerdictHeader(report: report),

            if (state.summary.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SummaryCard(text: state.summary),
            ],

            if (highFirst.isNotEmpty) ...[
              const SizedBox(height: 22),
              const _SectionLabel('What is wrong with this bill'),
              const SizedBox(height: 12),
              for (var i = 0; i < highFirst.length; i++) ...[
                FlagCard(flag: highFirst[i], index: i + 1),
                if (i != highFirst.length - 1) const SizedBox(height: 14),
              ],
            ],

            if (report.notes.isNotEmpty) ...[
              const SizedBox(height: 22),
              NotesCard(notes: report.notes),
            ],

            const SizedBox(height: 22),
            BillSummaryCard(bill: bill),

            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: () {
                context.read<AppState>().reset();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              icon: const Icon(Icons.document_scanner_rounded),
              label: const Text('Scan another bill'),
            ),
            const SizedBox(height: 14),
            const _Disclaimer(),
          ],
        ),
      ),
    );
  }

  void _showRawText(BuildContext context, String rawText) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, controller) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Raw scanned text',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Exactly what the on-device OCR read.',
                  style:
                      TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.infoSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      rawText,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: AppColors.textSecondary,
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  final String text;
  const _SummaryCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.record_voice_over_rounded,
                  color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'WHAT TO SAY AT THE COUNTER',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: AppColors.accent.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'This is a prototype that reads a photo of a bill and applies four '
          'published rules. It is informational, not legal advice, and a '
          'misread bill can produce a wrong result — always check the printed '
          'bill before raising a complaint.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
      );
}
