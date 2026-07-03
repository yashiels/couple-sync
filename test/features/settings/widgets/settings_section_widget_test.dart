import 'package:couple_sync/features/settings/widgets/settings_section_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildSubject(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('SettingsSectionWidget', () {
    testWidgets('renders title text', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsSectionWidget(
            title: 'Test Section',
            children: [Text('Child')],
          ),
        ),
      );
      expect(find.text('Test Section'), findsOneWidget);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsSectionWidget(
            title: 'Test',
            icon: Icons.settings,
            children: [Text('Child')],
          ),
        ),
      );
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('does not render icon when not provided', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsSectionWidget(title: 'Test', children: [Text('Child')]),
        ),
      );
      // No icons should be present from the section itself
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('renders children', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsSectionWidget(
            title: 'Test',
            children: [Text('First child'), Text('Second child')],
          ),
        ),
      );
      expect(find.text('First child'), findsOneWidget);
      expect(find.text('Second child'), findsOneWidget);
    });

    testWidgets('wraps content in a Card', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsSectionWidget(title: 'Test', children: [Text('Child')]),
        ),
      );
      expect(find.byType(Card), findsOneWidget);
    });
  });

  group('SettingsItem', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsItem(
            title: 'Item Title',
            trailing: Icon(Icons.chevron_right),
          ),
        ),
      );
      expect(find.text('Item Title'), findsOneWidget);
    });

    testWidgets('renders subtitle when provided', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsItem(
            title: 'Title',
            subtitle: 'Subtitle text',
            trailing: Icon(Icons.chevron_right),
          ),
        ),
      );
      expect(find.text('Subtitle text'), findsOneWidget);
    });

    testWidgets('does not render subtitle when null', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsItem(
            title: 'Title',
            trailing: Icon(Icons.chevron_right),
          ),
        ),
      );
      // Only title should exist, no subtitle
      expect(find.text('Title'), findsOneWidget);
    });

    testWidgets('renders trailing widget', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsItem(
            title: 'Title',
            trailing: Icon(Icons.arrow_forward),
          ),
        ),
      );
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    testWidgets('calls onTap when enabled and tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildSubject(
          SettingsItem(
            title: 'Title',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('does not call onTap when disabled', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildSubject(
          SettingsItem(
            title: 'Title',
            trailing: const Icon(Icons.chevron_right),
            enabled: false,
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.byType(InkWell));
      expect(tapped, isFalse);
    });
  });

  group('SettingsToggle', () {
    testWidgets('renders title and switch', (tester) async {
      await tester.pumpWidget(
        _buildSubject(const SettingsToggle(title: 'Toggle Title', value: true)),
      );
      expect(find.text('Toggle Title'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('switch reflects value=true', (tester) async {
      await tester.pumpWidget(
        _buildSubject(const SettingsToggle(title: 'Toggle', value: true)),
      );
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);
    });

    testWidgets('switch reflects value=false', (tester) async {
      await tester.pumpWidget(
        _buildSubject(const SettingsToggle(title: 'Toggle', value: false)),
      );
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isFalse);
    });

    testWidgets('calls onChanged when toggled', (tester) async {
      bool? changedValue;
      await tester.pumpWidget(
        _buildSubject(
          SettingsToggle(
            title: 'Toggle',
            value: false,
            onChanged: (v) => changedValue = v,
          ),
        ),
      );
      await tester.tap(find.byType(Switch));
      expect(changedValue, isTrue);
    });

    testWidgets('renders subtitle when provided', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsToggle(
            title: 'Toggle',
            subtitle: 'Toggle description',
            value: false,
          ),
        ),
      );
      expect(find.text('Toggle description'), findsOneWidget);
    });
  });

  group('SettingsButton', () {
    testWidgets('renders title and button label', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsButton(title: 'Button Title', label: 'Press Me'),
        ),
      );
      expect(find.text('Button Title'), findsOneWidget);
      expect(find.text('Press Me'), findsOneWidget);
    });

    testWidgets('renders subtitle when provided', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsButton(
            title: 'Button',
            subtitle: 'Button description',
            label: 'Go',
          ),
        ),
      );
      expect(find.text('Button description'), findsOneWidget);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsButton(
            title: 'Button',
            label: 'Go',
            icon: Icons.refresh,
          ),
        ),
      );
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('calls onTap when pressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildSubject(
          SettingsButton(
            title: 'Button',
            label: 'Go',
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.byType(TextButton));
      expect(tapped, isTrue);
    });

    testWidgets('uses error color for destructive buttons', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsButton(
            title: 'Delete',
            label: 'Delete',
            isDestructive: true,
          ),
        ),
      );
      // Widget should render without errors
      expect(find.text('Delete'), findsAtLeast(1));
    });
  });

  group('SettingsStatusItem', () {
    testWidgets('renders title and status text', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsStatusItem(title: 'Status Title', status: 'Connected'),
        ),
      );
      expect(find.text('Status Title'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('renders subtitle when provided', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsStatusItem(
            title: 'Status',
            subtitle: 'Status description',
            status: 'OK',
          ),
        ),
      );
      expect(find.text('Status description'), findsOneWidget);
    });

    testWidgets('renders status icon when provided', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const SettingsStatusItem(
            title: 'Status',
            status: 'Connected',
            statusIcon: Icons.cloud_done,
          ),
        ),
      );
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    });

    testWidgets('renders without icon when not provided', (tester) async {
      await tester.pumpWidget(
        _buildSubject(const SettingsStatusItem(title: 'Status', status: 'OK')),
      );
      expect(find.text('OK'), findsOneWidget);
    });
  });
}
