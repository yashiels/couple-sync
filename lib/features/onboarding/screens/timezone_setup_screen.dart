import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/timezone_helper.dart';
import '../../../core/router/routes.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../../../services/providers/sync_provider.dart';
import '../../../services/sync_service.dart';

/// Timezone setup screen for onboarding.
/// Auto-detects device timezone and allows user to search and select a different one.
/// Saves the selected timezone to Firestore and navigates to the next onboarding step.
class TimezoneSetupScreen extends ConsumerStatefulWidget {
  const TimezoneSetupScreen({super.key});

  @override
  ConsumerState<TimezoneSetupScreen> createState() => _TimezoneSetupScreenState();
}

class _TimezoneSetupScreenState extends ConsumerState<TimezoneSetupScreen> {
  String? _selectedTimezone;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeTimezone();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Initialize timezone data and auto-detect device timezone.
  Future<void> _initializeTimezone() async {
    try {
      await TimezoneHelper.initialize();
      final detectedTimezone = await TimezoneHelper.detectDeviceTimezone();
      
      if (mounted) {
        setState(() {
          _selectedTimezone = detectedTimezone;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedTimezone = 'UTC';
          _isLoading = false;
        });
      }
    }
  }

  /// Save selected timezone to Firestore and navigate to next step.
  Future<void> _saveAndContinue() async {
    if (_selectedTimezone == null) return;
    
    final uid = ref.read(authStateProvider).uid;
    if (uid == null) {
      setState(() {
        _error = 'Not authenticated. Please sign in again.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final syncService = ref.read(syncServiceProvider);
      await syncService.updateUser(uid, {'timezone': _selectedTimezone});

      // Refresh the auth state to pick up the new timezone
      await ref.read(authStateProvider.notifier).refreshProfile();

      if (mounted) {
        context.go(AppRoutes.pairing);
      }
    } on SyncException catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = _mapSyncError(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = 'An unexpected error occurred. Please try again.';
        });
      }
    }
  }

  String _mapSyncError(SyncException e) {
    switch (e.code) {
      case 'http-401':
        return 'Permission denied. Please sign in again.';
      case 'http-503':
      case 'http-network':
        return 'Network error. Please check your connection.';
      default:
        return 'Failed to save timezone. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Your Timezone'),
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header section
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'We detected your timezone',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_selectedTimezone != null)
                        _SelectedTimezoneCard(
                          timezone: _selectedTimezone!,
                          isSelected: true,
                          onTap: () {}, // Already selected
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Or search for a different timezone:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                // Search field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search timezones...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // Error message
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Card(
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Timezone list
                Expanded(
                  child: _TimezoneList(
                    searchQuery: _searchQuery,
                    selectedTimezone: _selectedTimezone,
                    onTimezoneSelected: (timezone) {
                      setState(() {
                        _selectedTimezone = timezone;
                      });
                    },
                    scrollController: _scrollController,
                  ),
                ),

                // Continue button
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _selectedTimezone != null && !_isSaving
                            ? _saveAndContinue
                            : null,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_forward),
                        label: Text(_isSaving ? 'Saving...' : 'Continue'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Card widget displaying the selected timezone.
class _SelectedTimezoneCard extends StatelessWidget {
  final String timezone;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectedTimezoneCard({
    required this.timezone,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = TimezoneHelper.getDisplayName(timezone);
    final offset = TimezoneHelper.getCurrentOffset(timezone);
    final currentTime = TimezoneHelper.getCurrentTime(timezone);

    return Card(
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$offset • Current time: $currentTime',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrollable list of timezones grouped by region.
class _TimezoneList extends StatelessWidget {
  final String searchQuery;
  final String? selectedTimezone;
  final Function(String) onTimezoneSelected;
  final ScrollController scrollController;

  const _TimezoneList({
    required this.searchQuery,
    required this.selectedTimezone,
    required this.onTimezoneSelected,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final groupedTimezones = searchQuery.isEmpty
        ? TimezoneHelper.getTimezonesGroupedByRegion()
        : TimezoneHelper.searchTimezonesGroupedByRegion(searchQuery);

    if (groupedTimezones.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No timezones found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    final regions = groupedTimezones.keys.toList();

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      itemCount: regions.length,
      itemBuilder: (context, regionIndex) {
        final region = regions[regionIndex];
        final timezones = groupedTimezones[region]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Region header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                region,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            // Timezones in this region
            ...timezones.map((timezone) => _TimezoneTile(
                  timezone: timezone,
                  isSelected: selectedTimezone == timezone,
                  onTap: () => onTimezoneSelected(timezone),
                )),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

/// Individual timezone list tile.
class _TimezoneTile extends StatelessWidget {
  final String timezone;
  final bool isSelected;
  final VoidCallback onTap;

  const _TimezoneTile({
    required this.timezone,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = TimezoneHelper.getDisplayName(timezone);
    final offset = TimezoneHelper.getCurrentOffset(timezone);
    final currentTime = TimezoneHelper.getCurrentTime(timezone);

    return ListTile(
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.outline,
      ),
      title: Text(
        displayName,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        '$offset • $currentTime',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      tileColor: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
    );
  }
}
