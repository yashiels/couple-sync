import 'package:flutter/material.dart';
import '../../core/models/time_block.dart';
import '../../core/theme/app_colors.dart';

/// Widget to display a time block event on the calendar.
/// Shows block details with color coding based on ownership and category.
class BlockEventWidget extends StatelessWidget {
  final TimeBlock block;
  final bool isCurrentUser;
  final VoidCallback? onTap;

  const BlockEventWidget({
    super.key,
    required this.block,
    required this.isCurrentUser,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Get category color
    final categoryColor = _getCategoryColor(block.category, isDark);
    
    // Apply opacity/alpha for visual distinction between user and partner
    final displayColor = isCurrentUser 
        ? categoryColor
        : categoryColor.withValues(alpha: 0.6);
    
    // Format time range
    final startTime = _formatTime(block.startDateTime);
    final endTime = _formatTime(block.endDateTime);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: displayColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isCurrentUser 
                ? categoryColor
                : categoryColor.withValues(alpha: 0.8),
            width: 1,
          ),
        ),
        child: ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                block.title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _getTextColor(categoryColor),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (block.durationMinutes >= 60) ...[
                const SizedBox(height: 2),
                Text(
                  '$startTime - $endTime',
                  style: TextStyle(
                    fontSize: 9,
                    color: _getTextColor(categoryColor).withValues(alpha: 0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Get color for block category
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

  /// Get contrasting text color for background
  Color _getTextColor(Color backgroundColor) {
    // Calculate luminance to determine if text should be light or dark
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  /// Format time to HH:mm
  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// Dialog to show block details when tapped
class BlockDetailDialog extends StatelessWidget {
  final TimeBlock block;
  final bool isCurrentUser;

  const BlockDetailDialog({
    super.key,
    required this.block,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final categoryColor = _getCategoryColor(block.category, isDark);
    
    final startTime = _formatTime(block.startDateTime);
    final endTime = _formatTime(block.endDateTime);
    final date = _formatDate(block.startDateTime);
    
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: categoryColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              block.title,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow(
            context,
            Icons.person_outline,
            'Owner',
            isCurrentUser ? 'You' : 'Partner',
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            context,
            Icons.calendar_today_outlined,
            'Date',
            date,
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            context,
            Icons.access_time,
            'Time',
            '$startTime - $endTime',
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            context,
            Icons.timelapse,
            'Duration',
            _formatDuration(block.durationMinutes),
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            context,
            Icons.category_outlined,
            'Category',
            _getCategoryLabel(block.category),
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            context,
            Icons.source_outlined,
            'Source',
            block.source == TimeBlockSource.google ? 'Google Calendar' : 'Manual',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

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

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDate(DateTime dateTime) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year}';
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) {
      return '$hours hr';
    }
    return '$hours hr $mins min';
  }

  String _getCategoryLabel(TimeBlockCategory category) {
    switch (category) {
      case TimeBlockCategory.work:
        return 'Work';
      case TimeBlockCategory.study:
        return 'Study';
      case TimeBlockCategory.commute:
        return 'Commute';
      case TimeBlockCategory.exercise:
        return 'Exercise';
      case TimeBlockCategory.social:
        return 'Social';
      case TimeBlockCategory.meals:
        return 'Meals';
      case TimeBlockCategory.sleep:
        return 'Sleep';
      case TimeBlockCategory.personal:
        return 'Personal';
      case TimeBlockCategory.other:
        return 'Other';
    }
  }
}
