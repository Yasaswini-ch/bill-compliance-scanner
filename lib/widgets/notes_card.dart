import 'package:flutter/material.dart';

import '../models/compliance_flag.dart';
import '../theme/app_theme.dart';

/// Lists the checks that could not be run. Deliberately styled as
/// information rather than as an accusation: an unreadable bill is not an
/// illegal one, and the app should never let the two blur together.
class NotesCard extends StatelessWidget {
  final List<DataNote> notes;

  const NotesCard({super.key, required this.notes});

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.infoSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  notes.length == 1
                      ? '1 check could not be run'
                      : '${notes.length} checks could not be run',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...notes.map(
            (note) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7, right: 10),
                    child: SizedBox(
                      width: 6,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      note.message,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
