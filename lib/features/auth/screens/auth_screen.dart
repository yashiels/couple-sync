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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Clear any previous errors when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authStateProvider.notifier).clearError();
    });
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
    Theme.of(context);

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

/// Google logo widget.
class _GoogleLogo extends StatelessWidget {
  final double size;

  const _GoogleLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

/// Custom painter for the Google "G" logo.
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    final width = size.width;
    final height = size.height;
    final strokeWidth = width * 0.12;

    // Draw a simplified "G" using colored segments
    final center = Offset(width / 2, height / 2);
    final radius = width / 2 - strokeWidth / 2;

    // Blue segment (right side and top right)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, // Start at top
      2.7489, // ~157 degrees
      false,
      paint..strokeWidth = strokeWidth..style = PaintingStyle.stroke..strokeCap = StrokeCap.round,
    );

    // Red segment (top left)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      1.1781, // ~67.5 degrees
      0.7854, // ~45 degrees
      false,
      paint,
    );

    // Yellow segment (left side)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      1.9635, // ~112.5 degrees
      0.7854, // ~45 degrees
      false,
      paint,
    );

    // Green segment (bottom left)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      2.7489, // ~157.5 degrees
      0.7854, // ~45 degrees
      false,
      paint,
    );

    // Draw horizontal bar in center (part of "G")
    paint.color = const Color(0xFF4285F4);
    paint.style = PaintingStyle.fill;
    final barWidth = width * 0.35;
    final barHeight = strokeWidth;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          center.dx - barWidth * 0.3,
          center.dy - barHeight / 2,
          barWidth,
          barHeight,
        ),
        Radius.circular(barHeight / 2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
