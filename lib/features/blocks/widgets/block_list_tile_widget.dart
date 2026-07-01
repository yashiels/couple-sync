import 'package:flutter/material.dart';
import '../../../core/models/time_block.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';

/// Widget to display a single time block in the block management list.
/// Shows title, time range, category color, and source badge.
class BlockListTileWidget extends StatelessWidget {
  final TimeBlock block;
  final bool isCurrentUser;
  final VoidCallback? onTap;

  const BlockListTileWidget({
    super.key,
    required this.block,
    required this.isCurrentUser,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categoryColor = _getCategoryColor(block.category, isDark);
    final timeRange = _formatTimeRange();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(
                color: categoryColor,
                width: 4,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Category indicator circle
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: categoryColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row with source badge
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              block.title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildSourceBadge(context),
                        ],
                      ),
                      const SizedBox(height: 4),
                      
                      // Time range
                      Text(
                        timeRange,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      
                      // Owner indicator
                      Text(
                        isCurrentUser ? 'You' : 'Partner',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isCurrentUser 
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Navigation indicator
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build the source badge (manual or google)
  Widget _buildSourceBadge(BuildContext context) {
    final isManual = block.source == TimeBlockSource.manual;
    final badgeColor = isManual 
      ? Theme.of(context).colorScheme.primary
      : Colors.green;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isManual ? Icons.edit : Icons.sync,
            size: 12,
            color: badgeColor,
          ),
          const SizedBox(width: 4),
          Text(
            isManual ? 'Manual' : 'Google',
            style: TextStyle(
              fontSize: 11,
              color: badgeColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Get category color based on category and theme
  Color _getCategoryColor(TimeBlockCategory category, bool isDark) {
    switch (category) {
      case TimeBlockCategory.work:
        return isDark ? AppColors.categoryWorkDark : AppColors.categoryWorkLight;
      case TimeBlockCategory.study:
        return isDark ? AppColors.categoryStudyDark : AppColors.categoryStudyLight;
      case TimeBlockCategory.commute:
        return isDark ? AppColors.categoryCommuteDark : AppColors.categoryCommuteLight;
      case TimeBlockCategory.exercise:
        return isDark ? AppColors.categoryExerciseDark : AppColors.categoryExerciseLight;
      case TimeBlockCategory.social:
        return isDark ? AppColors.categorySocialDark : AppColors.categorySocialLight;
      case TimeBlockCategory.meals:
        return isDark ? AppColors.categoryMealsDark : AppColors.categoryMealsLight;
      case TimeBlockCategory.sleep:
        return isDark ? AppColors.categorySleepDark : AppColors.categorySleepLight;
      case TimeBlockCategory.personal:
        return isDark ? AppColors.categoryPersonalDark : AppColors.categoryPersonalLight;
      case TimeBlockCategory.other:
        return isDark ? AppColors.categoryOtherDark : AppColors.categoryOtherLight;
    }
  }

  /// Format time range as "HH:mm - HH:mm"
  String _formatTimeRange() {
    final start = block.startDateTime.toLocal();
    final end = block.endDateTime.toLocal();

    final startStr = formatTimeHm(start);
    final endStr = formatTimeHm(end);

    // Check if same day
    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return '${_formatDate(start)} • $startStr - $endStr';
    } else {
      return '${_formatDate(start)} $startStr - ${_formatDate(end)} $endStr';
    }
  }

  /// Locale-aware short date — `d MMM` via [formatMonth].
  String _formatDate(DateTime dateTime) =>
      '${dateTime.day} ${formatMonth(dateTime)}';
}
