import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/money.dart';
import '../theme/app_theme.dart';

/// Shows what the scan actually read off the bill, so the user can tell at a
/// glance whether a verdict rests on a good read or a patchy one.
class BillSummaryCard extends StatelessWidget {
  final Bill bill;

  const BillSummaryCard({super.key, required this.bill});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('What the scan read',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              _QualityChip(quality: bill.readQuality),
            ],
          ),
          const SizedBox(height: 14),
          _row('Subtotal', _money(bill.subtotal)),
          _row('Service charge', _serviceCharge()),
          _row('CGST', _tax(bill.cgst)),
          _row('SGST', _tax(bill.sgst)),
          if (bill.gstCombined.isFound) _row('GST', _tax(bill.gstCombined)),
          _row('Total', _money(bill.total)),
          _row('GSTIN', bill.gstin.isFound ? bill.gstin.value! : _label(bill.gstin)),
          if (bill.items.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            Text('${bill.items.length} items read',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textSecondary,
                )),
            const SizedBox(height: 8),
            ...bill.items.take(8).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.quantity > 1
                                ? '${item.name} ×${item.quantity}'
                                : item.name,
                            style: const TextStyle(
                                fontSize: 14.5, color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          formatRupees(item.price),
                          style: const TextStyle(
                              fontSize: 14.5, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );

  String _money(Detected<double> field) =>
      field.isFound ? formatRupees(field.value) : _label(field);

  String _tax(Detected<TaxComponent> field) {
    if (!field.isFound) return _label(field);
    final t = field.value!;
    final amount = t.amount != null ? formatRupees(t.amount) : '—';
    return t.percent != null ? '$amount  (${formatPercent(t.percent)})' : amount;
  }

  String _serviceCharge() {
    final field = bill.serviceCharge;
    if (!field.isFound) return _label(field);
    final sc = field.value!;
    final amount = sc.amount != null ? formatRupees(sc.amount) : '—';
    final pct = sc.percentLabel != null ? '  (${sc.percentLabel})' : '';
    final waived = sc.looksOptedOut ? '  · waived' : '';
    return '$amount$pct$waived';
  }

  /// Distinguishes "the bill does not have this" from "the scan could not
  /// read this" — the same distinction the rule engine relies on.
  String _label(Detected field) =>
      field.isAbsent ? 'not on bill' : 'not readable';
}

class _QualityChip extends StatelessWidget {
  final ReadQuality quality;

  const _QualityChip({required this.quality});

  @override
  Widget build(BuildContext context) {
    final (String text, Color color) = switch (quality) {
      ReadQuality.good => ('Good read', AppColors.success),
      ReadQuality.partial => ('Partial read', AppColors.warning),
      ReadQuality.poor => ('Poor read', AppColors.alert),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}
