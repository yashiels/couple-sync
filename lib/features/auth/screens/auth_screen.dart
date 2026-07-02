import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/providers/auth_state_provider.dart';

/// Authentication screen with Google and Apple Sign-In buttons.
/// Displays user-friendly error messages and handles loading states.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _isEmailLoading = false;
  String? _errorMessage;

  // ponytail: dev-only email controllers; only allocated when running against
  // the Firebase emulators (USE_FIREBASE_EMULATOR dart-define). The prefilled
  // credentials are guarded to debug+emulator builds so they can never leak
  // into a release artifact.
  static const _useEmulator =
      bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false);
  static const bool _allowDevCreds = kDebugMode && _useEmulator;
  final TextEditingController _emailController = TextEditingController(
      text: _allowDevCreds ? 'partnerA@example.com' : '');
  final TextEditingController _passwordController =
      TextEditingController(text: _allowDevCreds ? 'password123' : '');

  @override
  void initState() {
    super.initState();
    // Clear any previous errors when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authStateProvider.notifier).clearError();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleEmailSignIn() async {
    if (_isEmailLoading) return;
    setState(() {
      _isEmailLoading = true;
      _errorMessage = null;
    });
    try {
      final success = await ref
          .read(authStateProvider.notifier)
          .signInWithEmail(_emailController.text, _passwordController.text);
      if (!success) {
        _errorMessage = ref.read(authStateProvider.notifier).lastError;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEmailLoading = false;
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isGoogleLoading || _isAppleLoading) return;

    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });

    final success = await ref.read(authStateProvider.notifier).signInWithGoogle();

    if (mounted) {
      setState(() {
        _isGoogleLoading = false;
        if (!success) {
          _errorMessage = ref.read(authStateProvider.notifier).lastError;
        }
      });
    }
  }

  Future<void> _handleAppleSignIn() async {
    if (_isGoogleLoading || _isAppleLoading) return;

    setState(() {
      _isAppleLoading = true;
      _errorMessage = null;
    });

    final success = await ref.read(authStateProvider.notifier).signInWithApple();

    if (mounted) {
      setState(() {
        _isAppleLoading = false;
        if (!success) {
          _errorMessage = ref.read(authStateProvider.notifier).lastError;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App logo/icon (decorative, excluded from accessibility)
                Semantics(
                  excludeSemantics: true,
                  child: Icon(
                    Icons.favorite,
                    size: 80,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),

                // App name
                Text(
                  'Couple Sync',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Tagline
                Text(
                  'Find time together, no matter the distance',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Error message with accessibility
                if (_errorMessage != null) ...[
                  Semantics(
                    liveRegion: true,
                    container: true,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Semantics(
                            excludeSemantics: true,
                            child: Icon(
                              Icons.error_outline,
                              color: colorScheme.error,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Semantics(
                              excludeSemantics: true,
                              child: Icon(
                                Icons.close,
                                color: colorScheme.onErrorContainer,
                                size: 20,
                              ),
                            ),
                            tooltip: 'Dismiss error',
                            onPressed: () {
                              setState(() {
                                _errorMessage = null;
                              });
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Google Sign-In button
                Semantics(
                  button: true,
                  enabled: !_isGoogleLoading && !_isAppleLoading,
                  label: 'Continue with Google',
                  hint: _isGoogleLoading ? 'Signing in with Google' : 'Sign in using your Google account',
                  child: _SignInButton(
                    text: 'Continue with Google',
                    icon: _buildGoogleIcon(),
                    isLoading: _isGoogleLoading,
                    onPressed: _handleGoogleSignIn,
                  ),
                ),
                const SizedBox(height: 16),

                // Apple Sign-In button
                Semantics(
                  button: true,
                  enabled: !_isGoogleLoading && !_isAppleLoading,
                  label: 'Continue with Apple',
                  hint: _isAppleLoading ? 'Signing in with Apple' : 'Sign in using your Apple ID',
                  child: _SignInButton(
                    text: 'Continue with Apple',
                    icon: _buildAppleIcon(),
                    isLoading: _isAppleLoading,
                    onPressed: _handleAppleSignIn,
                    isAppleButton: true,
                  ),
                ),
                const SizedBox(height: 32),

                // ponytail: dev-only email sign-in. Renders only against the
                // Firebase emulators so prod auth stays Google/Apple-only.
                if (_useEmulator) ...[
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'DEV — Emulator mode',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isEmailLoading ? null : _handleEmailSignIn,
                    child: _isEmailLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue with Email (dev)'),
                  ),
                  const SizedBox(height: 32),
                ],

                // Terms and privacy
                Text(
                  'By signing in, you agree to our Terms of Service\nand Privacy Policy',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleIcon() {
    return const _GoogleLogo(size: 20);
  }

  Widget _buildAppleIcon() {
    return const Icon(
      Icons.apple,
      size: 20,
      color: Colors.white,
    );
  }
}

/// Custom sign-in button with loading state.
class _SignInButton extends StatelessWidget {
  final String text;
  final Widget icon;
  final bool isLoading;
  final VoidCallback onPressed;
  final bool isAppleButton;

  const _SignInButton({
    required this.text,
    required this.icon,
    required this.isLoading,
    required this.onPressed,
    this.isAppleButton = false,
  });

  @override
  Widget build(BuildContext context) {
    // Apple button uses black background, Google uses white/outline
    final backgroundColor = isAppleButton ? Colors.black : Colors.white;
    final foregroundColor = isAppleButton ? Colors.white : Colors.black87;
    final borderColor = isAppleButton ? Colors.black : Colors.grey.shade300;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(8),
        enableFeedback: true,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                  ),
                )
              else
                icon,
              const SizedBox(width: 12),
              Text(
                text,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Google logo widget — renders the official `assets/icons/google_g.png`
/// asset instead of a hand-painted CustomPainter.
class _GoogleLogo extends StatelessWidget {
  final double size;

  const _GoogleLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/icons/google_g.png',
        fit: BoxFit.contain,
        semanticLabel: 'Google logo',
      ),
    );
  }
}
