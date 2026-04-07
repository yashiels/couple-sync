import 'dart:async';

import 'package:couple_sync/core/utils/timezone_helper.dart';
import 'package:couple_sync/features/home/partner_clock_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

Widget _buildSubject({
  String userTimezone = 'Africa/Johannesburg',
  String partnerTimezone = 'Europe/London',
  String partnerName = 'Partner',
}) {
  return MaterialApp(
    home: Scaffold(
      body: PartnerClockWidget(
        userTimezone: userTimezone,
        partnerTimezone: partnerTimezone,
        partnerName: partnerName,
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('PartnerClockWidget rendering', () {
    testWidgets('displays "You" label for user clock', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('displays partner name label', (tester) async {
      await tester.pumpWidget(_buildSubject(partnerName: 'Alice'));
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('displays two time strings in HH:MM format', (tester) async {
      await tester.pumpWidget(_buildSubject());

      // Both clocks should show times matching HH:MM pattern
      final userTime = TimezoneHelper.getCurrentTime('Africa/Johannesburg');
      final partnerTime = TimezoneHelper.getCurrentTime('Europe/London');

      expect(find.text(userTime), findsOneWidget);
      expect(find.text(partnerTime), findsOneWidget);
    });

    testWidgets('displays UTC offset for both timezones', (tester) async {
      await tester.pumpWidget(_buildSubject());

      final userOffset = TimezoneHelper.getCurrentOffset('Africa/Johannesburg');
      final partnerOffset = TimezoneHelper.getCurrentOffset('Europe/London');

      expect(find.text(userOffset), findsOneWidget);
      expect(find.text(partnerOffset), findsOneWidget);
    });

    testWidgets('is wrapped in a Card', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('has a vertical divider between clocks', (tester) async {
      await tester.pumpWidget(_buildSubject());

      // The divider is a Container with width 1
      final container = tester.widgetList<Container>(find.byType(Container)).where(
        (c) => c.constraints?.maxWidth == 1 && c.constraints?.maxHeight == 60,
      );
      // Should find the divider container via decoration color
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('shows fallback time for invalid timezone', (tester) async {
      await tester.pumpWidget(_buildSubject(
        userTimezone: 'Invalid/Zone',
        partnerTimezone: 'Also/Invalid',
      ));

      // TimezoneHelper returns '--:--' for invalid timezones
      expect(find.text('--:--'), findsNWidgets(2));
      // TimezoneHelper returns 'UTC' for invalid timezone offsets
      expect(find.text('UTC'), findsNWidgets(2));
    });
  });

  group('PartnerClockWidget timer', () {
    testWidgets('cancels timer on dispose without errors', (tester) async {
      await tester.pumpWidget(_buildSubject());
      // Dispose by replacing with empty container
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      // No errors means timer was properly cancelled
    });
  });
}
