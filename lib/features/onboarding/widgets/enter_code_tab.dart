import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../../../services/providers/sync_provider.dart';
import '../../../services/sync_service.dart';

/// Tab for entering partner's invite code and redeeming it.
/// Calls the redeemInvite Cloud Function and handles all error cases.
///
/// [initialCode] pre-fills the text field when the user arrives via a deep
/// link (e.g. https://coupleschedule.app/invite/ABC123).
class EnterCodeTab extends ConsumerStatefulWidget {
  final String? initialCode;

  const EnterCodeTab({super.key, this.initialCode});

  @override
  ConsumerState<EnterCodeTab> createState() => _EnterCodeTabState();
}

class _EnterCodeTabState extends ConsumerState<EnterCodeTab> {
  late final TextEditingController _codeController;
  bool _isLoading = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    // Pre-fill the code field when arriving via deep link.
    final preFill = widget.initialCode?.toUpperCase() ?? '';
    _codeController = TextEditingController(text: preFill);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.vpn_key_outlined,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 24),
          Text(
            'Enter Partner\'s Code',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          const Text(
            'Enter the code your partner shared with you',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),

          // Code Input Field
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
            decoration: InputDecoration(
              hintText: 'XXXXXX',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
            ),
            onChanged: (value) {
              // Convert to uppercase as user types
              _codeController.value = _codeController.value.copyWith(
                text: value.toUpperCase(),
                selection: TextSelection.collapsed(offset: value.length),
              );
            },
          ),
          const SizedBox(height: 24),

          // Redeem Button
          FilledButton.icon(
            onPressed: _isLoading ? null : _redeemCode,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle),
            label: Text(_isLoading ? 'Redeeming...' : 'Redeem Code'),
          ),

          // Success Message
          if (_success != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _success!,
                    style: const TextStyle(color: Colors.green),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ],

          // Error Message
          if (_error != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Redeems the invite code via the backend (POST /invites/:code/redeem).
  Future<void> _redeemCode() async {
    final code = _codeController.text.trim().toUpperCase();

    // Validate code format
    if (code.length != 6) {
      setState(() {
        _error = 'Code must be 6 characters';
        _success = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });

    try {
      final uid = ref.read(authStateProvider).uid;
      if (uid == null) {
        throw Exception('Not authenticated');
      }

      final syncService = ref.read(syncServiceProvider);
      final coupleId = await syncService.redeemInvite(code);

      if (coupleId.isNotEmpty) {
        setState(() {
          _success = 'Successfully paired with your partner!';
          _isLoading = false;
        });

        // Refresh user profile to update coupleId, which triggers router navigation
        await ref.read(authStateProvider.notifier).refreshProfile();
      } else {
        throw Exception('Failed to create couple');
      }
    } on SyncException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'http-404':
          errorMessage = 'Invalid invite code';
          break;
        case 'http-409':
          // Expired / own code / already paired — backend returns 409 with a
          // message; surface a generic but accurate hint.
          errorMessage = (e.originalError?.toString() ?? '')
                  .contains('expired')
              ? 'This invite code has expired'
              : (e.originalError?.toString() ?? '').contains('own code')
                  ? 'You cannot redeem your own code'
                  : (e.originalError?.toString() ?? '')
                          .contains('already paired')
                      ? 'You are already paired with a partner'
                      : 'This invite code is no longer valid';
          break;
        case 'http-401':
          errorMessage = 'You do not have permission to redeem this code';
          break;
        case 'http-503':
          errorMessage = 'Service temporarily unavailable. Please try again';
          break;
        default:
          errorMessage = 'Failed to redeem code. Please try again';
      }

      setState(() {
        _error = errorMessage;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'An unexpected error occurred. Please try again';
        _isLoading = false;
      });
    }
  }
}
