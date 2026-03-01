import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: _OnboardingBody(),
    );
  }
}

class _OnboardingBody extends StatefulWidget {
  const _OnboardingBody();

  @override
  State<_OnboardingBody> createState() => _OnboardingBodyState();
}

class _OnboardingBodyState extends State<_OnboardingBody> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _PageData(
      icon: Icons.sync_rounded,
      title: 'Sync Your Calendars',
      body: 'Connect Google or Apple Calendar to automatically share your busy times.',
      color: AppColors.lavender,
    ),
    _PageData(
      icon: Icons.favorite_border_rounded,
      title: 'Find Free Windows',
      body: 'Our engine finds the moments when you are both free, factoring in time zones.',
      color: AppColors.rose,
    ),
    _PageData(
      icon: Icons.notifications_active_rounded,
      title: 'Get Notified',
      body: 'Receive alerts when a new free window opens up — never miss a chance to connect.',
      color: AppColors.skyBlue,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => _OnboardingPage(data: _pages[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _page == i ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _page == i ? AppColors.roseDeep : AppColors.lavender,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    if (_page < _pages.length - 1) {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  child: Text(_page < _pages.length - 1 ? 'Next' : 'Get Started'),
                ),
              ],
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: data.color.withAlpha(50),
              shape: BoxShape.circle,
            ),
            child: Icon(data.icon, size: 60, color: data.color),
          ),
          const SizedBox(height: 40),
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
