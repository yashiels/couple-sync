import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/time_block.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/block_labels.dart';
import '../../../core/utils/format_utils.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../../../services/providers/couple_providers.dart';
import '../widgets/block_list_tile_widget.dart';

/// Block management screen with filtering and navigation to edit/view.
/// Displays all time blocks (user's and partner's) with source and category filtering.
class BlockManagementScreen extends ConsumerStatefulWidget {
  const BlockManagementScreen({super.key});

  @override
  ConsumerState<BlockManagementScreen> createState() => _BlockManagementScreenState();
}

class _BlockManagementScreenState extends ConsumerState<BlockManagementScreen> {
  // Filter state
  TimeBlockSource? _sourceFilter; // null = all
  TimeBlockCategory? _categoryFilter; // null = all

  /// Get filtered blocks based on current filter state
  List<TimeBlock> _filterBlocks(List<TimeBlock> blocks) {
    var filtered = blocks;

    // Apply source filter
    if (_sourceFilter != null) {
      filtered = filtered.where((b) => b.source == _sourceFilter).toList();
    }

    // Apply category filter
    if (_categoryFilter != null) {
      filtered = filtered.where((b) => b.category == _categoryFilter).toList();
    }

    // Sort by start time
    filtered.sort((a, b) => a.startUtc.compareTo(b.startUtc));

    return filtered;
  }

  /// Navigate to block form (edit or new)
  void _navigateToBlockForm({String? blockId}) {
    context.go(
      AppRoutes.blockForm,
      extra: BlockFormArgs(blockId: blockId),
    );
  }

  /// Handle block tap - navigate based on source
  void _onBlockTap(TimeBlock block) {
    if (block.source == TimeBlockSource.manual) {
      // Manual blocks can be edited
      _navigateToBlockForm(blockId: block.id);
    } else {
      // Google-sourced blocks are read-only
      _showReadOnlyView(block);
    }
  }

  /// Show read-only block details dialog
  void _showReadOnlyView(TimeBlock block) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(block.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Source', block.source == TimeBlockSource.manual ? 'Manual' : 'Google'),
            const SizedBox(height: 8),
            _buildDetailRow('Category', block.category.label),
            const SizedBox(height: 8),
            _buildDetailRow('Type', block.type.label),
            const SizedBox(height: 8),
            _buildDetailRow('Time', _formatDateTimeRange(block)),
            const SizedBox(height: 8),
            if (block.isRecurring) ...[
              _buildDetailRow('Recurs', 'Yes'),
              const SizedBox(height: 8),
            ],
            _buildDetailRow('Visibility', block.visibility.label),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (block.source == TimeBlockSource.manual)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToBlockForm(blockId: block.id);
              },
              child: const Text('Edit'),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(value),
        ),
      ],
    );
  }

  String _formatDateTimeRange(TimeBlock block) {
    final start = block.startDateTime.toLocal();
    final end = block.endDateTime.toLocal();

    final startStr = '${_formatDate(start)} ${formatTimeHm(start)}';
    final endStr = formatTimeHm(end);

    if (start.year == end.year && start.month == end.month && start.day == end.day) {
      return '$startStr - $endStr';
    } else {
      return '$startStr - ${_formatDate(end)} $endStr';
    }
  }

  /// Locale-aware short date — `d MMM yyyy` via [formatMonth].
  String _formatDate(DateTime dateTime) =>
      '${dateTime.day} ${formatMonth(dateTime)} ${dateTime.year}';

  /// Show filter bottom sheet
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter Blocks',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              // Source filter
              Text(
                'Source',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildFilterChip(
                    label: 'All',
                    selected: _sourceFilter == null,
                    onSelected: (selected) {
                      setModalState(() => _sourceFilter = null);
                    },
                  ),
                  _buildFilterChip(
                    label: 'Manual',
                    selected: _sourceFilter == TimeBlockSource.manual,
                    onSelected: (selected) {
                      setModalState(() => _sourceFilter = TimeBlockSource.manual);
                    },
                  ),
                  _buildFilterChip(
                    label: 'Google',
                    selected: _sourceFilter == TimeBlockSource.google,
                    onSelected: (selected) {
                      setModalState(() => _sourceFilter = TimeBlockSource.google);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Category filter
              Text(
                'Category',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterChip(
                    label: 'All',
                    selected: _categoryFilter == null,
                    onSelected: (selected) {
                      setModalState(() => _categoryFilter = null);
                    },
                  ),
                  ...TimeBlockCategory.values.map((category) => _buildFilterChip(
                    label: category.label,
                    selected: _categoryFilter == category,
                    onSelected: (selected) {
                      setModalState(() => _categoryFilter = category);
                    },
                  )),
                ],
              ),
              const SizedBox(height: 24),

              // Apply button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {}); // refresh filtered list with new filters
                  },
                  child: const Text('Apply Filters'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required void Function(bool) onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authStateProvider);
    final currentUserId = authState.uid;
    final blocksAsync = ref.watch(userBlocksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Block Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
            tooltip: 'Filter blocks',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(userBlocksProvider),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: blocksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64,
                  color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Failed to load blocks: $error',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(userBlocksProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (blocks) => _buildBlocksList(blocks, currentUserId),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToBlockForm(),
        tooltip: 'Add new block',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBlocksList(List<TimeBlock> blocks, String? currentUserId) {
    final theme = Theme.of(context);
    final filteredBlocks = _filterBlocks(blocks);

    if (filteredBlocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64,
                color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              blocks.isEmpty
                ? 'No blocks yet\nTap + to create your first block'
                : 'No blocks match your filters',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Show active filters indicator
    final hasActiveFilters = _sourceFilter != null || _categoryFilter != null;

    return Column(
      children: [
        if (hasActiveFilters)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.primaryContainer,
            child: Row(
              children: [
                Icon(
                  Icons.filter_list,
                  size: 16,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Filters active: ${filteredBlocks.length} of ${blocks.length} blocks',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _sourceFilter = null;
                      _categoryFilter = null;
                    });
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(userBlocksProvider),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: filteredBlocks.length,
              itemBuilder: (context, index) {
                final block = filteredBlocks[index];
                return BlockListTileWidget(
                  block: block,
                  isCurrentUser: block.userId == currentUserId,
                  onTap: () => _onBlockTap(block),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
