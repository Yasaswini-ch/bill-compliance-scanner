import 'package:flutter/material.dart';

import '../models/compliance_flag.dart';
import '../models/money.dart';
import '../theme/app_theme.dart';

/// One compliance violation, presented so the headline is readable across a
/// room and the detail rewards stepping closer.
class FlagCard extends StatelessWidget {
  final ComplianceFlag flag;
  final int index;

  const FlagCard({super.key, required this.flag, required this.index});

  bool get _isHigh => flag.severity == FlagSeverity.high;

  Color get _accent => _isHigh ? AppColors.alert : AppColors.warning;
  Color get _surface =>
      _isHigh ? AppColors.alertSurface : AppColors.warningSurface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.35), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header strip: severity and the amount at stake.
          Container(
            width: double.infinity,
            color: _surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _isHigh ? 'HIGH SEVERITY' : 'MEDIUM SEVERITY',
                  style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                if (flag.amountAffected != null && flag.amountAffected! > 0)
                  Text(
                    formatRupees(flag.amountAffected),
                    style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(flag.title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(flag.explanation, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.infoSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.gavel_rounded,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          flag.citedRule,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
