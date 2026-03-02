import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/pairing_providers.dart';

/// Screen for connecting with a partner via a 6-character invite code.
///
/// Two tabs: "Share Code" generates and displays the user's own invite code,
/// and "Enter Code" redeems a partner's code.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect with Partner'),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.roseDeep,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.roseDeep,
          tabs: const [
            Tab(icon: Icon(Icons.share_rounded), text: 'Share Code'),
            Tab(icon: Icon(Icons.vpn_key_rounded), text: 'Enter Code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _ShareCodeTab(),
          _EnterCodeTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Share Code Tab
// ---------------------------------------------------------------------------

class _ShareCodeTab extends ConsumerStatefulWidget {
  const _ShareCodeTab();

  @override
  ConsumerState<_ShareCodeTab> createState() => _ShareCodeTabState();
}

class _ShareCodeTabState extends ConsumerState<_ShareCodeTab> {
  String? _code;
  bool _loading = false;
  bool _copied = false;

  // In a real app we'd get the uid from auth providers
  static const _demoUid = 'demo_uid';

  Future<void> _generateCode() async {
    setState(() => _loading = true);
    try {
      final code = await ref.read(pairingNotifierProvider.notifier).generateCode(_demoUid);
      setState(() => _code = code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyCode() async {
    if (_code == null) return;
    await Clipboard.setData(ClipboardData(text: _code!));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.favorite_rounded, size: 64, color: AppColors.rose),
          const SizedBox(height: 20),
          Text(
            'Share Your Code',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Give this code to your partner so they can connect with you.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 36),
          if (_code != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                _code!,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 10,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Expires in 48 hours',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _copyCode,
              icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded),
              label: Text(_copied ? 'Copied!' : 'Copy Code'),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _generateCode, child: const Text('Generate New Code')),
          ] else ...[
            ElevatedButton(
              onPressed: _loading ? null : _generateCode,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Generate Invite Code'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Enter Code Tab
// ---------------------------------------------------------------------------

class _EnterCodeTab extends ConsumerStatefulWidget {
  const _EnterCodeTab();

  @override
  ConsumerState<_EnterCodeTab> createState() => _EnterCodeTabState();
}

class _EnterCodeTabState extends ConsumerState<_EnterCodeTab> {
  final _controller = TextEditingController();
  String? _error;

  static const _demoRedeemerUid = 'demo_redeemer_uid';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Code must be 6 characters.');
      return;
    }
    setState(() => _error = null);
    try {
      await ref.read(pairingNotifierProvider.notifier).redeemCode(
            code: code,
            redeemerUid: _demoRedeemerUid,
          );
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(pairingNotifierProvider);
    final loading = status == PairingStatus.loading;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.person_add_rounded, size: 64, color: AppColors.skyBlue),
          const SizedBox(height: 20),
          Text(
            'Enter Partner\'s Code',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Type the 6-character code your partner shared with you.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 36),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'ABC123',
              errorText: _error,
              prefixIcon: const Icon(Icons.vpn_key_rounded),
            ),
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 6,
            ),
            textAlign: TextAlign.center,
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: loading ? null : _connect,
            child: loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Connect'),
          ),
        ],
      ),
    );
  }
}
