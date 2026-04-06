import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';

/// Main application widget that provides the app shell.
/// Wraps MaterialApp.router with theme configuration and routing.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  /// Current theme mode (light/dark/system)
  ThemeMode _themeMode = ThemeMode.system;

  /// Router configuration
  /// TODO: Configure actual routes in STORY-006
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const PlaceholderHomeScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(
        child: Text('Page not found: ${state.error}'),
      ),
    ),
  );

  /// Toggle between light and dark themes
  void toggleTheme() {
    setState(() {
      if (_themeMode == ThemeMode.light) {
        _themeMode = ThemeMode.dark;
      } else if (_themeMode == ThemeMode.dark) {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.light;
      }
    });
  }

  /// Set specific theme mode
  void setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      // App configuration
      title: 'Couple Sync',
      debugShowCheckedModeBanner: false,
      
      // Theme configuration
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      
      // Router configuration
      routerConfig: _router,
      
      // Accessibility
      builder: (context, child) {
        // Ensure text scaling respects user preferences
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.4),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Placeholder home screen until actual screens are implemented in STORY-027+
/// This will be replaced with the real home screen during UI implementation phase.
class PlaceholderHomeScreen extends StatelessWidget {
  const PlaceholderHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Couple Sync'),
        actions: [
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: () {
              // Access MyApp state to toggle theme
              final myAppState = context.findAncestorStateOfType<_MyAppState>();
              myAppState?.toggleTheme();
            },
            tooltip: 'Toggle theme',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.favorite,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome to Couple Sync',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Find mutual free time with your partner',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // Demo of category colors
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildCategoryChip(context, 'Work'),
                  _buildCategoryChip(context, 'Study'),
                  _buildCategoryChip(context, 'Commute'),
                  _buildCategoryChip(context, 'Exercise'),
                  _buildCategoryChip(context, 'Social'),
                  _buildCategoryChip(context, 'Meals'),
                  _buildCategoryChip(context, 'Sleep'),
                  _buildCategoryChip(context, 'Personal'),
                  _buildCategoryChip(context, 'Other'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(BuildContext context, String category) {
    final color = AppTheme.getCategoryColor(
      category,
      Theme.of(context).brightness,
    );
    
    return Chip(
      label: Text(category),
      backgroundColor: color.withOpacity(0.2),
      labelStyle: TextStyle(
        color: color,
        fontWeight: FontWeight.w500,
      ),
      side: BorderSide(color: color),
    );
  }
}
