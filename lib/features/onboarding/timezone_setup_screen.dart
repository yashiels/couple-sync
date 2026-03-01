import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../core/theme/app_theme.dart';
import '../../shared/providers/auth_providers.dart';

class TimezoneSetupScreen extends ConsumerStatefulWidget {
  const TimezoneSetupScreen({super.key});

  @override
  ConsumerState<TimezoneSetupScreen> createState() => _TimezoneSetupScreenState();
}

class _TimezoneSetupScreenState extends ConsumerState<TimezoneSetupScreen> {
  String? _selected;
  String _query = '';
  bool _saving = false;

  late final List<String> _zones;

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _zones = tz.timeZoneDatabase.locations.keys.toList()..sort();
    // Pre-select local
    try {
      _selected = tz.local.name;
    } catch (_) {
      _selected = 'UTC';
    }
  }

  List<String> get _filtered {
    if (_query.isEmpty) return _zones;
    final q = _query.toLowerCase();
    return _zones.where((z) => z.toLowerCase().contains(q)).toList();
  }

  Future<void> _save() async {
    if (_selected == null) return;
    setState(() => _saving = true);
    final user = ref.read(currentUserProvider);
    if (user != null) {
      await ref.read(authServiceProvider).updateTimezone(user.uid, _selected!);
    }
    if (mounted) context.go('/pairing');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Timezone')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Where are you located?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'We use this to calculate your overlap windows accurately.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search timezone...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (context, i) {
                final zone = _filtered[i];
                return ListTile(
                  leading: Icon(
                    Icons.schedule_rounded,
                    color: zone == _selected ? AppColors.roseDeep : AppColors.textHint,
                  ),
                  title: Text(zone),
                  selected: zone == _selected,
                  selectedColor: AppColors.roseDeep,
                  onTap: () => setState(() => _selected = zone),
                  trailing: zone == _selected ? const Icon(Icons.check_circle_rounded, color: AppColors.roseDeep) : null,
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save & Continue'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
