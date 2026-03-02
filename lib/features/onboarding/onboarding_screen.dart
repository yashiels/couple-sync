import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

/// Three-page onboarding walkthrough shown after first sign-up.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _PageData(
      icon: Icons.sync_rounded,
      title: 'Sync Your Calendars',
      body: 'Connect Google or Apple Calendar to automatically share your busy times with your partner.',
      color: AppColors.lavender,
    ),
    _PageData(
      icon: Icons.favorite_border_rounded,
      title: 'Find Free Windows',
      body: 'Our overlap engine finds the moments when you are both free, factoring in time zones automatically.',
      color: AppColors.rose,
    ),
    _PageData(
      icon: Icons.notifications_active_rounded,
      title: 'Never Miss a Moment',
      body: 'Get notified the instant a new free window opens up — so you can plan your next call or date.',
      color: AppColors.skyBlue,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: () => context.go('/timezone-setup'),
                child: const Text('Skip'),
              ),
            ),
            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _OnboardingPage(data: _pages[i]),
              ),
            ),
            // Indicators + button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _page == i ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _page == i ? AppColors.roseDeep : AppColors.lavender,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: () {
                      if (_page < _pages.length - 1) {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        context.go('/timezone-setup');
                      }
                    },
                    child: Text(_page < _pages.length - 1 ? 'Next' : 'Get Started'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final _PageData data;
  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              color: data.color.withAlpha(50),
              shape: BoxShape.circle,
            ),
            child: Icon(data.icon, size: 64, color: data.color),
          ),
          const SizedBox(height: 44),
          Text(data.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 16),
          Text(data.body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _PageData {
  final IconData icon;
  final String title;
  final String body;
  final Color color;
  const _PageData({required this.icon, required this.title, required this.body, required this.color});
}
