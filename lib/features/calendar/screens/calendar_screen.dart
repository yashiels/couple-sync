import 'package:flutter/material.dart';
import '../week_view_screen.dart';

/// Calendar screen wrapper that displays the week view.
/// STORY-028: Calendar week view with blocks and overlap windows.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const WeekViewScreen();
  }
}
