import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/time_block.dart';
import '../../../core/router/routes.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../../../services/providers/firestore_provider.dart';
import '../widgets/recurrence_picker_widget.dart';

/// Form screen for creating or editing manual time blocks.
/// Handles validation, timezone conversion, recurrence, and Firestore operations.
class BlockFormScreen extends ConsumerStatefulWidget {
  final BlockFormArgs? args;

  const BlockFormScreen({super.key, this.args});

  @override
  ConsumerState<BlockFormScreen> createState() => _BlockFormScreenState();
}

class _BlockFormScreenState extends ConsumerState<BlockFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  
  TimeBlockType _type = TimeBlockType.busy;
  TimeBlockCategory _category = TimeBlockCategory.other;
  TimeBlockVisibility _visibility = TimeBlockVisibility.bothPartners;
  
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;
  
  String _timezone = 'UTC';
  String? _recurrenceRule;
  
  bool _isLoading = false;
  bool _isDeleting = false;
  String? _error;
  
  TimeBlock? _existingBlock;

  @override
  void initState() {
    super.initState();
    
    // Initialize dates
    final now = DateTime.now();
    _startDate = widget.args?.initialDate ?? now;
    _startTime = TimeOfDay.fromDateTime(_startDate);
    _endDate = _startDate.add(const Duration(hours: 1));
    _endTime = TimeOfDay.fromDateTime(_endDate);
    
    // Load existing block if editing
    if (widget.args?.blockId != null) {
      _loadBlock();
    }
    
    // Set timezone from user profile
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(authStateProvider).profile;
      if (profile?.timezone != null && profile!.timezone.isNotEmpty) {
        setState(() {
          _timezone = profile.timezone;
        });
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  /// Load existing block data for editing
  Future<void> _loadBlock() async {
    final blockId = widget.args?.blockId;
    if (blockId == null) return;
    
    final profile = ref.read(authStateProvider).profile;
    if (profile?.coupleId == null) {
      setState(() {
        _error = 'Not in a couple. Cannot edit blocks.';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final doc = await FirebaseFirestore.instance
          .collection('timeblocks')
          .doc(profile!.coupleId)
          .collection('blocks')
          .doc(blockId)
          .get();
      
      if (doc.exists) {
        final block = TimeBlock.fromJson(doc.data()!, doc.id);
        setState(() {
          _existingBlock = block;
          _titleController.text = block.title;
          _type = block.type;
          _category = block.category;
          _visibility = block.visibility;
          _timezone = block.timezone;
          _recurrenceRule = block.recurrenceRule;
          _startDate = block.startDateTime;
          _startTime = TimeOfDay.fromDateTime(_startDate);
          _endDate = block.endDateTime;
          _endTime = TimeOfDay.fromDateTime(_endDate);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Block not found';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load block: $e';
      });
    }
  }

  /// Get start time as UTC milliseconds
  int get _startUtc {
    final dateTime = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    return dateTime.toUtc().millisecondsSinceEpoch;
  }

  /// Get end time as UTC milliseconds
  int get _endUtc {
    final dateTime = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      _endTime.hour,
      _endTime.minute,
    );
    return dateTime.toUtc().millisecondsSinceEpoch;
  }

  /// Validate that end time is after start time
  bool get _isEndTimeValid => _endUtc > _startUtc;

  /// Save the block (create or update)
  Future<void> _saveBlock() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (!_isEndTimeValid) {
      setState(() {
        _error = 'End time must be after start time';
      });
      return;
    }
    
    final authState = ref.read(authStateProvider);
    final uid = authState.uid;
    final profile = authState.profile;
    
    if (uid == null || profile?.coupleId == null) {
      setState(() {
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
      
      final block = TimeBlock(
        userId: uid,
        title: _titleController.text.trim(),
        type: _type,
        category: _category,
        startUtc: _startUtc,
        endUtc: _endUtc,
        timezone: _timezone,
        recurrenceRule: _recurrenceRule,
        source: TimeBlockSource.manual,
        visibility: _visibility,
        createdAt: _existingBlock?.createdAt ?? DateTime.now().toUtc(),
      );
      
      if (_existingBlock != null) {
        // Update existing block
        await firestoreService.updateBlock(
          profile!.coupleId!,
          widget.args!.blockId!,
          block.toJson(),
        );
      } else {
        // Create new block
        await firestoreService.createBlock(profile!.coupleId!, block);
      }
      
      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to save block: $e';
      });
    }
  }

  /// Delete the block with confirmation
  Future<void> _deleteBlock() async {
    if (_existingBlock == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Block'),
        content: const Text('Are you sure you want to delete this time block? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    final profile = ref.read(authStateProvider).profile;
    if (profile?.coupleId == null || widget.args?.blockId == null) return;
    
    setState(() {
      _isDeleting = true;
      _error = null;
    });
    
    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      await firestoreService.deleteBlock(
        profile!.coupleId!,
        widget.args!.blockId!,
      );
      
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _isDeleting = false;
        _error = 'Failed to delete block: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.args?.blockId != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Block' : 'New Block'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _isDeleting ? null : _deleteBlock,
            ),
        ],
      ),
      body: _isLoading && _existingBlock == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title field
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Title is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Type dropdown
                    DropdownButtonFormField<TimeBlockType>(
                      initialValue: _type,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                      ),
                      items: TimeBlockType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(_getTypeLabel(type)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _type = value ?? TimeBlockType.busy;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Category dropdown
                    DropdownButtonFormField<TimeBlockCategory>(
                      initialValue: _category,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: TimeBlockCategory.values.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(_getCategoryLabel(category)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _category = value ?? TimeBlockCategory.other;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Visibility dropdown
                    DropdownButtonFormField<TimeBlockVisibility>(
                      initialValue: _visibility,
                      decoration: const InputDecoration(
                        labelText: 'Visibility',
                        border: OutlineInputBorder(),
                      ),
                      items: TimeBlockVisibility.values.map((visibility) {
                        return DropdownMenuItem(
                          value: visibility,
                          child: Text(_getVisibilityLabel(visibility)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _visibility = value ?? TimeBlockVisibility.bothPartners;
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    // Start date/time
                    Text(
                      'Start',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              '${_startDate.day}/${_startDate.month}/${_startDate.year}',
                            ),
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _startDate,
                                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                                setState(() {
                                  _startDate = date;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time),
                            label: Text(
                              _startTime.format(context),
                            ),
                            onPressed: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: _startTime,
                              );
                              if (time != null) {
                                setState(() {
                                  _startTime = time;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // End date/time
                    Text(
                      'End',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              '${_endDate.day}/${_endDate.month}/${_endDate.year}',
                            ),
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _endDate,
                                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                                setState(() {
                                  _endDate = date;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time),
                            label: Text(
                              _endTime.format(context),
                            ),
                            onPressed: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: _endTime,
                              );
                              if (time != null) {
                                setState(() {
                                  _endTime = time;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    
                    // End time validation error
                    if (!_isEndTimeValid)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'End time must be after start time',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Timezone display
                    Text(
                      'Timezone: $_timezone',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),

                    // Recurrence picker
                    RecurrencePickerWidget(
                      initialRecurrenceRule: _recurrenceRule,
                      onChanged: (rrule) {
                        setState(() {
                          _recurrenceRule = rrule;
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    // Error message
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading || _isDeleting ? null : _saveBlock,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(isEditing ? 'Update Block' : 'Create Block'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String _getTypeLabel(TimeBlockType type) {
    switch (type) {
      case TimeBlockType.busy:
        return 'Busy';
      case TimeBlockType.free:
        return 'Free';
      case TimeBlockType.tentative:
        return 'Tentative';
    }
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

  String _getVisibilityLabel(TimeBlockVisibility visibility) {
    switch (visibility) {
      case TimeBlockVisibility.bothPartners:
        return 'Both Partners';
      case TimeBlockVisibility.onlyMe:
        return 'Only Me';
    }
  }
}
