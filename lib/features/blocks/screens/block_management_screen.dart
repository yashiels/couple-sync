import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/time_block.dart';
import '../../../core/router/routes.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../../../services/providers/firestore_provider.dart';
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
  
  List<TimeBlock> _blocks = [];
  bool _isLoading = true;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _loadBlocks();
  }

  /// Load all blocks for the couple
  Future<void> _loadBlocks() async {
    final authState = ref.read(authStateProvider);
    final profile = authState.profile;
    
    if (profile?.coupleId == null || authState.uid == null) {
      setState(() {
        _isLoading = false;
        _error = 'Not authenticated or not in a couple';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      final blocks = await firestoreService.getBlocks(
        profile!.coupleId!,
        authState.uid!,
      );
      
      setState(() {
        _blocks = blocks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load blocks: $e';
      });
    }
  }

  /// Get filtered blocks based on current filter state
  List<TimeBlock> get _filteredBlocks {
    var filtered = _blocks;
    
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
      _navigateToBlockForm(blockId: null); // TODO: Need block ID from Firestore
      _showReadOnlyView(block);
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
            _buildDetailRow('Category', _getCategoryLabel(block.category)),
            const SizedBox(height: 8),
            _buildDetailRow('Type', _getTypeLabel(block.type)),
            const SizedBox(height: 8),
            _buildDetailRow('Time', _formatDateTimeRange(block)),
            const SizedBox(height: 8),
            if (block.isRecurring) ...[
              _buildDetailRow('Recurs', 'Yes'),
              const SizedBox(height: 8),
            ],
            _buildDetailRow('Visibility', _getVisibilityLabel(block.visibility)),
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
                // TODO: Navigate to edit form with block ID
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Edit functionality coming soon')),
                );
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
    final start = block.startDateTime;
    final end = block.endDateTime;
    
    final startStr = '${_formatDate(start)} ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final endStr = '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    
    if (start.year == end.year && start.month == end.month && start.day == end.day) {
      return '$startStr - $endStr';
    } else {
      return '$startStr - ${_formatDate(end)} $endStr';
    }
  }

  String _formatDate(DateTime dateTime) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year}';
  }

  String _getCategoryLabel(TimeBlockCategory category) {
    switch (category) {
      case TimeBlockCategory.work: return 'Work';
      case TimeBlockCategory.study: return 'Study';
      case TimeBlockCategory.commute: return 'Commute';
      case TimeBlockCategory.exercise: return 'Exercise';
      case TimeBlockCategory.social: return 'Social';
      case TimeBlockCategory.meals: return 'Meals';
      case TimeBlockCategory.sleep: return 'Sleep';
      case TimeBlockCategory.personal: return 'Personal';
      case TimeBlockCategory.other: return 'Other';
    }
  }

  String _getTypeLabel(TimeBlockType type) {
    switch (type) {
      case TimeBlockType.busy: return 'Busy';
      case TimeBlockType.free: return 'Free';
      case TimeBlockType.tentative: return 'Tentative';
    }
  }

  String _getVisibilityLabel(TimeBlockVisibility visibility) {
    switch (visibility) {
      case TimeBlockVisibility.bothPartners: return 'Both Partners';
      case TimeBlockVisibility.onlyMe: return 'Only Me';
    }
  }

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
                      setState(() => _sourceFilter = null);
                    },
                  ),
                  _buildFilterChip(
                    label: 'Manual',
                    selected: _sourceFilter == TimeBlockSource.manual,
                    onSelected: (selected) {
                      setModalState(() => _sourceFilter = TimeBlockSource.manual);
                      setState(() => _sourceFilter = TimeBlockSource.manual);
                    },
                  ),
                  _buildFilterChip(
                    label: 'Google',
                    selected: _sourceFilter == TimeBlockSource.google,
                    onSelected: (selected) {
                      setModalState(() => _sourceFilter = TimeBlockSource.google);
                      setState(() => _sourceFilter = TimeBlockSource.google);
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
                      setState(() => _categoryFilter = null);
                    },
                  ),
                  ...TimeBlockCategory.values.map((category) => _buildFilterChip(
                    label: _getCategoryLabel(category),
                    selected: _categoryFilter == category,
                    onSelected: (selected) {
                      setModalState(() => _categoryFilter = category);
                      setState(() => _categoryFilter = category);
                    },
                  )),
                ],
              ),
              const SizedBox(height: 24),
              
              // Apply button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
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
    final authState = ref.watch(authStateProvider);
    final currentUserId = authState.uid;
    
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
            onPressed: _loadBlocks,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(currentUserId),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToBlockForm(),
        child: const Icon(Icons.add),
        tooltip: 'Add new block',
      ),
    );
  }

  Widget _buildBody(String? currentUserId) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadBlocks,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    final filteredBlocks = _filteredBlocks;
    
    if (filteredBlocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.event_busy, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _blocks.isEmpty 
                ? 'No blocks yet\nTap + to create your first block'
                : 'No blocks match your filters',
              style: const TextStyle(color: Colors.grey),
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
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              children: [
                Icon(
                  Icons.filter_list,
                  size: 16,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Filters active: ${filteredBlocks.length} of ${_blocks.length} blocks',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontSize: 12,
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
            onRefresh: _loadBlocks,
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
