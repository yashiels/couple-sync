import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../services/providers/auth_state_provider.dart';

/// Tab for entering partner's invite code and redeeming it.
/// Calls the redeemInvite Cloud Function and handles all error cases.
class EnterCodeTab extends ConsumerStatefulWidget {
  const EnterCodeTab({super.key});

  @override
  ConsumerState<EnterCodeTab> createState() => _EnterCodeTabState();
}

class _EnterCodeTabState extends ConsumerState<EnterCodeTab> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _success;

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

  /// Redeems the invite code by calling the redeemInvite Cloud Function.
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

      // Call the redeemInvite Cloud Function
      final callable = FirebaseFunctions.instance.httpsCallable('redeemInvite');
      final result = await callable({'code': code});

      final data = result.data as Map<String, dynamic>;
      final coupleId = data['coupleId'] as String?;

      if (coupleId != null) {
        setState(() {
          _success = 'Successfully paired with your partner!';
          _isLoading = false;
        });

        // Refresh user profile to update coupleId, which triggers router navigation
        await ref.read(authStateProvider.notifier).refreshProfile();
      } else {
        throw Exception('Failed to create couple');
      }
    } on FirebaseFunctionsException catch (e) {
      String errorMessage;
      
      // Map error codes to user-friendly messages
      switch (e.code) {
        case 'invalid-argument':
          errorMessage = 'Invalid code format';
          break;
        case 'not-found':
          errorMessage = 'Invalid invite code';
          break;
        case 'failed-precondition':
          // Check for specific error messages from Cloud Function
          if (e.message?.contains('expired') ?? false) {
            errorMessage = 'This invite code has expired';
          } else if (e.message?.contains('own code') ?? false) {
            errorMessage = 'You cannot redeem your own code';
          } else if (e.message?.contains('already paired') ?? false) {
            errorMessage = 'You are already paired with a partner';
          } else {
            errorMessage = 'This invite code is no longer valid';
          }
          break;
        case 'permission-denied':
          errorMessage = 'You do not have permission to redeem this code';
          break;
        case 'unavailable':
          errorMessage = 'Service temporarily unavailable. Please try again';
          break;
        case 'deadline-exceeded':
          errorMessage = 'Request timed out. Please try again';
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
