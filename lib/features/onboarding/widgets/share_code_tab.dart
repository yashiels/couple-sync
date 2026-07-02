import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../../../services/providers/sync_provider.dart';

/// Tab for sharing invite codes with partner.
/// Generates a 6-character alphanumeric uppercase code that can be copied or shared.
class ShareCodeTab extends ConsumerStatefulWidget {
  const ShareCodeTab({super.key});

  @override
  ConsumerState<ShareCodeTab> createState() => _ShareCodeTabState();
}

class _ShareCodeTabState extends ConsumerState<ShareCodeTab> {
  String? _inviteCode;
  bool _isLoading = false;
  String? _error;
  bool _showCopyConfirmation = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.people_outline,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 24),
          Text(
            'Share Your Code',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          const Text(
            'Generate a code to share with your partner',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),

          // Generate Code Button
          if (_inviteCode == null) ...[
            FilledButton.icon(
              onPressed: _isLoading ? null : _generateCode,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isLoading ? 'Generating...' : 'Generate Code'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],

          // Display Code
          if (_inviteCode != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Your Invite Code',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _inviteCode!,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Copy Button
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_showCopyConfirmation)
                  const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: Icon(Icons.check, color: Colors.green),
                  ),
                FilledButton.tonalIcon(
                  onPressed: _copyCode,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy Code'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Share Button
            FilledButton.icon(
              onPressed: _shareCode,
              icon: const Icon(Icons.share),
              label: const Text('Share Code'),
            ),
          ],
        ],
      ),
    );
  }

  /// Generates an invite code via the backend (POST /invites). The server
  /// mintss the 6-char code and stores it with a 48h expiry.
  Future<void> _generateCode() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final uid = ref.read(authStateProvider).uid;
      if (uid == null) {
        throw Exception('Not authenticated');
      }

      final syncService = ref.read(syncServiceProvider);
      final code = await syncService.createInvite(uid);

      setState(() {
        _inviteCode = code;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to generate code. Please try again.';
        _isLoading = false;
      });
    }
  }

  /// Copies the invite code to clipboard.
  Future<void> _copyCode() async {
    if (_inviteCode == null) return;

    await Clipboard.setData(ClipboardData(text: _inviteCode!));
    
    setState(() {
      _showCopyConfirmation = true;
    });

    // Hide confirmation after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showCopyConfirmation = false;
        });
      }
    });
  }

  /// Shares the invite link using the system share sheet.
  /// The HTTPS URL is an App Link (Android) / Universal Link (iOS) that
  /// opens Couple Sync directly on devices where the app is installed.
  void _shareCode() {
    if (_inviteCode == null) return;

    final deepLink = 'https://coupleschedule.app/invite/$_inviteCode';
    Share.share(
      'Join me on Couple Sync!\n\nTap to open: $deepLink\n\nOr enter code manually: $_inviteCode',
      subject: 'Couple Sync Invite',
    );
  }
}
