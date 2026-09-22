import 'package:flutter/material.dart';

import '../models/compliance_flag.dart';
import '../models/money.dart';
import '../theme/app_theme.dart';

/// The single most important element on the result screen: the verdict,
/// sized to be read at a glance from several feet away.
class VerdictHeader extends StatelessWidget {
  final ComplianceReport report;

  const VerdictHeader({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    if (report.flags.isNotEmpty) return _buildViolations(context);
    if (report.isInconclusive) return _buildInconclusive(context);
    return _buildClean(context);
  }

  Widget _buildClean(BuildContext context) => _Banner(
        color: AppColors.success,
        surface: AppColors.successSurface,
        icon: Icons.verified_rounded,
        headline: 'No compliance issues detected',
        subline:
            'The service charge, GST rate, tax base and GSTIN were all checked '
            'and this bill passed every one.',
      );

  Widget _buildInconclusive(BuildContext context) => _Banner(
        color: AppColors.primary,
        surface: AppColors.infoSurface,
        icon: Icons.help_outline_rounded,
        headline: 'Not enough was readable to decide',
        subline:
            'No violations were found, but some checks could not run. This is '
            'not the same as a clean bill — see below.',
      );

  Widget _buildViolations(BuildContext context) {
    final count = report.flags.length;
    final money = report.totalAmountAffected;

    return _Banner(
      color: AppColors.alert,
      surface: AppColors.alertSurface,
      icon: Icons.report_problem_rounded,
      headline:
          '$count compliance ${count == 1 ? 'issue' : 'issues'} found',
      subline: money > 0
          ? '${formatRupees(money)} of this bill is affected. You can ask for '
              'it to be corrected before you pay.'
          : 'You can raise these with the restaurant before you pay.',
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final Color surface;
  final IconData icon;
  final String headline;
  final String subline;

  const _Banner({
    required this.color,
    required this.surface,
    required this.icon,
    required this.headline,
    required this.subline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    fontSize: 25,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: color == AppColors.primary
                        ? AppColors.primary
                        : color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            subline,
            style: const TextStyle(
              fontSize: 16,
              height: 1.4,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
