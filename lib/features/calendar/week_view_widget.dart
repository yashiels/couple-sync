import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/time_block.dart';
import '../../core/models/overlap_result.dart';
import '../../core/theme/app_colors.dart';
import 'block_event_widget.dart';

/// Week view widget displaying 7 days with time blocks and overlap windows.
/// Supports horizontal swipe pagination between weeks.
class WeekViewWidget extends StatefulWidget {
  /// Initial week to display (defaults to current week)
  final DateTime? initialWeek;
  
  /// User's time blocks for the visible week
  final List<TimeBlock> userBlocks;
  
  /// Partner's time blocks for the visible week
  final List<TimeBlock> partnerBlocks;
  
  /// Overlap windows for the visible week
  final List<OverlapWindow> overlapWindows;
  
  /// Current user's ID (to distinguish blocks)
  final String currentUserId;
  
  /// Callback when a new week is swiped to
  final void Function(DateTime weekStart)? onWeekChanged;
  
  /// Callback when FAB is pressed to add new block
  final VoidCallback? onAddBlock;

  const WeekViewWidget({
    super.key,
    this.initialWeek,
    this.userBlocks = const [],
    this.partnerBlocks = const [],
    this.overlapWindows = const [],
    required this.currentUserId,
    this.onWeekChanged,
    this.onAddBlock,
  });

  @override
  State<WeekViewWidget> createState() => _WeekViewWidgetState();
}

class _WeekViewWidgetState extends State<WeekViewWidget> {
  late PageController _pageController;
  late DateTime _currentWeekStart;
  
  // Use a baseline date for page indexing
  static const int _initialPage = 5200; // Large number to allow scrolling both directions
  
  @override
  void initState() {
    super.initState();
    _currentWeekStart = _getWeekStart(widget.initialWeek ?? DateTime.now());
    _pageController = PageController(initialPage: _initialPage);
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  
  /// Get the start of the week (Monday) for a given date
  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: weekday - 1));
  }
  
  /// Get week start for a given page index
  DateTime _getWeekStartFromPageIndex(int index) {
    final weeksOffset = index - _initialPage;
    return _currentWeekStart.add(Duration(days: weeksOffset * 7));
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            // Week header with navigation
            _buildWeekHeader(),
            
            // Day headers (Mon-Sun)
            _buildDayHeaders(),
            
            // Page view with week content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final weekStart = _getWeekStartFromPageIndex(index);
                  return _buildWeekContent(weekStart);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  /// Build week navigation header
  Widget _buildWeekHeader() {
    final monthYear = DateFormat('MMMM yyyy').format(_currentWeekStart);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _navigateWeek(-1),
          ),
          Text(
            monthYear,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _navigateWeek(1),
          ),
        ],
      ),
    );
  }
  
  /// Build day name headers (Mon, Tue, Wed, etc.)
  Widget _buildDayHeaders() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: List.generate(7, (index) {
          final dayDate = _currentWeekStart.add(Duration(days: index));
          final isToday = dayDate == todayDateOnly;
          
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    days[index],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isToday 
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${dayDate.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: isToday 
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
  
  /// Build the week content with time grid and blocks
  Widget _buildWeekContent(DateTime weekStart) {
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time labels column (left side)
          _buildTimeLabels(),
          
          // Days columns with blocks
          Expanded(
            child: Row(
              children: List.generate(7, (index) {
                final dayDate = weekStart.add(Duration(days: index));
                return Expanded(
                  child: _buildDayColumn(dayDate),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
  
  /// Build time labels on the left side
  Widget _buildTimeLabels() {
    return SizedBox(
      width: 48,
      child: Column(
        children: List.generate(24, (hour) {
          return Container(
            height: 60,
            alignment: Alignment.topRight,
            padding: const EdgeInsets.only(right: 8, top: 2),
            child: Text(
              _formatHour(hour),
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }),
      ),
    );
  }
  
  /// Build a single day column with blocks
  Widget _buildDayColumn(DateTime dayDate) {
    final dayStart = DateTime(dayDate.year, dayDate.month, dayDate.day);
    
    // Get blocks for this day
    final dayUserBlocks = _getBlocksForDay(widget.userBlocks, dayStart);
    final dayPartnerBlocks = _getBlocksForDay(widget.partnerBlocks, dayStart);
    final dayOverlaps = _getOverlapsForDay(widget.overlapWindows, dayStart);
    
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Stack(
        children: [
          // Hour grid lines
          _buildHourGrid(),
          
          // Overlap windows (rendered first, behind blocks)
          ...dayOverlaps.map((overlap) => _buildOverlapWidget(overlap, dayStart)),
          
          // User blocks
          ...dayUserBlocks.map((block) => _buildBlockWidget(block, dayStart, true)),
          
          // Partner blocks
          ...dayPartnerBlocks.map((block) => _buildBlockWidget(block, dayStart, false)),
        ],
      ),
    );
  }
  
  /// Build hour grid lines
  Widget _buildHourGrid() {
    return Column(
      children: List.generate(24, (hour) {
        return Container(
          height: 60,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
          ),
        );
      }),
    );
  }
  
  /// Build a block widget positioned in the day column
  Widget _buildBlockWidget(TimeBlock block, DateTime dayStart, bool isCurrentUser) {
    final blockStart = block.startDateTime;
    final blockEnd = block.endDateTime;
    
    // Calculate position and height
    final startMinutes = blockStart.hour * 60 + blockStart.minute;
    final endMinutes = blockEnd.hour * 60 + blockEnd.minute;
    final duration = endMinutes - startMinutes;
    
    final top = (startMinutes / 60) * 60; // 60 pixels per hour
    final height = (duration / 60) * 60;
    
    return Positioned(
      top: top,
      left: 2,
      right: 2,
      height: height.clamp(20.0, double.infinity),
      child: BlockEventWidget(
        block: block,
        isCurrentUser: isCurrentUser,
        onTap: () => _showBlockDetails(block, isCurrentUser),
      ),
    );
  }
  
  /// Build an overlap window widget
  Widget _buildOverlapWidget(OverlapWindow overlap, DateTime dayStart) {
    final overlapStart = overlap.startDateTime;
    final overlapEnd = overlap.endDateTime;
    
    // Calculate position and height
    final startMinutes = overlapStart.hour * 60 + overlapStart.minute;
    final endMinutes = overlapEnd.hour * 60 + overlapEnd.minute;
    final duration = endMinutes - startMinutes;
    
    final top = (startMinutes / 60) * 60;
    final height = (duration / 60) * 60;
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Use success color for overlap windows
    final overlapColor = isDark 
        ? AppColors.successDark.withOpacity(0.3)
        : AppColors.successLight.withOpacity(0.3);
    final borderColor = isDark 
        ? AppColors.successDark
        : AppColors.successLight;
    
    return Positioned(
      top: top,
      left: 2,
      right: 2,
      height: height.clamp(20.0, double.infinity),
      child: GestureDetector(
        onTap: () => _showOverlapDetails(overlap),
        child: Container(
          decoration: BoxDecoration(
            color: overlapColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: borderColor,
              width: 2,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.favorite,
              size: 14,
              color: borderColor,
            ),
          ),
        ),
      ),
    );
  }
  
  /// Filter blocks for a specific day
  List<TimeBlock> _getBlocksForDay(List<TimeBlock> blocks, DateTime dayStart) {
    final dayEnd = dayStart.add(const Duration(days: 1));
    
    return blocks.where((block) {
      final blockStart = block.startDateTime;
      final blockEnd = block.endDateTime;
      
      // Check if block overlaps with this day
      return blockStart.isBefore(dayEnd) && blockEnd.isAfter(dayStart);
    }).toList();
  }
  
  /// Filter overlap windows for a specific day
  List<OverlapWindow> _getOverlapsForDay(List<OverlapWindow> overlaps, DateTime dayStart) {
    final dayEnd = dayStart.add(const Duration(days: 1));
    
    return overlaps.where((overlap) {
      final overlapStart = overlap.startDateTime;
      final overlapEnd = overlap.endDateTime;
      
      return overlapStart.isBefore(dayEnd) && overlapEnd.isAfter(dayStart);
    }).toList();
  }
  
  /// Navigate to previous/next week
  void _navigateWeek(int direction) {
    final currentPage = _pageController.page?.round() ?? _initialPage;
    _pageController.animateToPage(
      currentPage + direction,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
  
  /// Handle page change
  void _onPageChanged(int index) {
    setState(() {
      _currentWeekStart = _getWeekStartFromPageIndex(index);
    });
    widget.onWeekChanged?.call(_currentWeekStart);
  }
  
  /// Show block details dialog
  void _showBlockDetails(TimeBlock block, bool isCurrentUser) {
    showDialog(
      context: context,
      builder: (context) => BlockDetailDialog(
        block: block,
        isCurrentUser: isCurrentUser,
      ),
    );
  }
  
  /// Show overlap window details dialog
  void _showOverlapDetails(OverlapWindow overlap) {
    showDialog(
      context: context,
      builder: (context) => _OverlapDetailDialog(overlap: overlap),
    );
  }
  
  /// Format hour to 24h format
  String _formatHour(int hour) {
    return '${hour.toString().padLeft(2, '0')}:00';
  }
}

/// Dialog to show overlap window details when tapped
class _OverlapDetailDialog extends StatelessWidget {
  final OverlapWindow overlap;

  const _OverlapDetailDialog({required this.overlap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final successColor = isDark ? AppColors.successDark : AppColors.successLight;
    
    final startTime = _formatTime(overlap.startDateTime);
    final endTime = _formatTime(overlap.endDateTime);
    final date = _formatDate(overlap.startDateTime);
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.favorite, color: successColor),
          const SizedBox(width: 8),
          const Text('Free Time Together'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            _formatDuration(overlap.durationMinutes),
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            context,
            Icons.star_outline,
            'Score',
            overlap.score.toStringAsFixed(1),
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            context,
            Icons.thumb_up_outlined,
            'Reasonable Hours',
            overlap.reasonableBoth ? 'Yes (for both)' : 'Mixed',
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
}
