import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/auth_providers.dart';
import '../../shared/providers/pairing_providers.dart';

enum _PairingTab { share, enter }

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  _PairingTab _tab = _PairingTab.share;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.groupedBackground,
      appBar: AppBar(
        backgroundColor: AppColors.groupedBackground,
        title: const Text('Pair with Partner'),
      ),
      body: Column(
        children: [
          // Segmented control
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: CupertinoSlidingSegmentedControl<_PairingTab>(
              groupValue: _tab,
              children: {
                _PairingTab.share: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text('Share Code', style: AppTypography.subhead),
                ),
                _PairingTab.enter: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text('Enter Code', style: AppTypography.subhead),
                ),
              },
              onValueChanged: (v) {
                if (v != null) setState(() => _tab = v);
              },
            ),
          ),
          Expanded(
            child: _tab == _PairingTab.share
                ? const _ShareCodeTab()
                : const _EnterCodeTab(),
          ),
        ],
      ),
    );
  }
}

// ── Share Code Tab ────────────────────────────────────────────────────────────

class _ShareCodeTab extends ConsumerStatefulWidget {
  const _ShareCodeTab();

  @override
  ConsumerState<_ShareCodeTab> createState() => _ShareCodeTabState();
}

class _ShareCodeTabState extends ConsumerState<_ShareCodeTab> {
  String? _code;
  bool _loading = false;
  bool _copied = false;

  Future<void> _generateCode() async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You must be signed in to generate a code.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final code =
          await ref.read(pairingNotifierProvider.notifier).generateCode(uid);
      if (mounted) setState(() => _code = code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyCode() async {
    if (_code == null) return;
    await Clipboard.setData(ClipboardData(text: _code!));
    if (!mounted) return;
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
          Icon(Icons.favorite_rounded, size: 64,
              color: AppColors.rose),
          const SizedBox(height: 20),
          Text(
            'Share Your Code',
            textAlign: TextAlign.center,
            style: AppTypography.title2,
          ),
          const SizedBox(height: 8),
          Text(
            'Give this code to your partner so they can pair with you.',
            textAlign: TextAlign.center,
            style: AppTypography.footnote,
          ),
          const SizedBox(height: 36),
          if (_code != null) ...[
            // Code display — large monospace in rounded card
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                _code!,
                style: AppTypography.largeTitle.copyWith(
                  fontFamily: 'Menlo',
                  letterSpacing: 10,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Generated just now \u2014 valid for 48 hours',
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _copyCode,
                icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded),
                label: Text(_copied ? 'Copied!' : 'Copy Code'),
              ),
            ),
            const SizedBox(height: 12),
            CupertinoButton(
              onPressed: _generateCode,
              child: Text('Generate New Code',
                  style: AppTypography.headline
                      .copyWith(color: AppColors.primary)),
            ),
          ] else ...[
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _generateCode,
                child: _loading
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text('Generate Invite Code'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Enter Code Tab ────────────────────────────────────────────────────────────

class _EnterCodeTab extends ConsumerStatefulWidget {
  const _EnterCodeTab();

  @override
  ConsumerState<_EnterCodeTab> createState() => _EnterCodeTabState();
}

class _EnterCodeTabState extends ConsumerState<_EnterCodeTab> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) {
      setState(() => _error = 'You must be signed in to pair.');
      return;
    }
    final code = _controller.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Code must be 6 characters.');
      return;
    }
    setState(() => _error = null);
    try {
      await ref.read(pairingNotifierProvider.notifier).redeemCode(
            code: code,
            redeemerUid: uid,
          );
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
          Icon(Icons.person_add_rounded, size: 64,
              color: AppColors.partnerBlue),
          const SizedBox(height: 20),
          Text(
            'Enter Partner\'s Code',
            textAlign: TextAlign.center,
            style: AppTypography.title2,
          ),
          const SizedBox(height: 8),
          Text(
            'Type the 6-character code your partner shared with you.',
            textAlign: TextAlign.center,
            style: AppTypography.footnote,
          ),
          const SizedBox(height: 36),
          // iOS-style rounded text field
          CupertinoTextField(
            controller: _controller,
            placeholder: 'ABC123',
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            style: AppTypography.title1.copyWith(letterSpacing: 6),
            textAlign: TextAlign.center,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            onSubmitted: (_) => _connect(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.footnote
                  .copyWith(color: AppColors.destructive),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: loading ? null : _connect,
              child: loading
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text('Pair'),
            ),
          ),
        ],
      ),
    );
  }
}
