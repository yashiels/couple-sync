import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

/// Structural validation of Firestore security rules.
///
/// These tests verify the rules file contains the expected access
/// patterns.  Full functional testing of rules requires the Firebase
/// Emulator Suite with @firebase/rules-unit-testing, which lives in
/// the functions/ directory.
void main() {
  late String rulesContent;

  setUpAll(() {
    final file = File('firestore.rules');
    expect(file.existsSync(), isTrue, reason: 'firestore.rules must exist');
    rulesContent = file.readAsStringSync();
  });

  group('Firestore rules structural checks', () {
    test('rules version is 2', () {
      expect(rulesContent, contains("rules_version = '2'"));
    });

    test('isCoupleMemember helper function exists', () {
      expect(rulesContent, contains('function isCoupleMemember(coupleId)'));
    });

    test('couples collection uses membership check', () {
      // Ensure it's not just "request.auth != null"
      expect(rulesContent, contains('isCoupleMemember(coupleId)'));
    });

    test('timeblocks collection uses membership check', () {
      final timeblockSection = _extractSection(rulesContent, 'timeblocks');
      expect(timeblockSection, contains('isCoupleMemember'));
    });

    test('overlaps collection uses membership check for reads', () {
      final overlapSection = _extractSection(rulesContent, 'overlaps');
      expect(overlapSection, contains('isCoupleMemember'));
    });

    test('overlaps collection blocks client writes', () {
      final overlapSection = _extractSection(rulesContent, 'overlaps');
      expect(overlapSection, contains('allow write: if false'));
    });

    test('users collection restricts writes to own document', () {
      expect(rulesContent, contains('request.auth.uid == userId'));
    });

    test('invites allow any authenticated user to read', () {
      final inviteSection = _extractSection(rulesContent, 'invites');
      expect(inviteSection, contains('allow read: if request.auth != null'));
    });

    test('invites restrict creation to the creator', () {
      final inviteSection = _extractSection(rulesContent, 'invites');
      expect(inviteSection, contains('createdByUid == request.auth.uid'));
    });

    test('recurringWindows blocks client writes', () {
      final rwSection = _extractSection(rulesContent, 'recurringWindows');
      expect(rwSection, contains('allow write: if false'));
    });

    test('patternRequests uses couple membership', () {
      final prSection = _extractSection(rulesContent, 'patternRequests');
      expect(prSection, contains('isCoupleMemember'));
    });

    test('no broad "allow read, write: if request.auth != null" on couples', () {
      // This was the old vulnerable rule — make sure it's gone
      final couplesSection = _extractSection(rulesContent, 'match /couples/{coupleId}');
      expect(
        couplesSection,
        isNot(contains('allow read, write: if request.auth != null')),
        reason: 'Couples should not have broad auth-only access',
      );
    });

    test('no broad "allow read, write: if request.auth != null" on timeblocks', () {
      final tbSection = _extractSection(rulesContent, 'timeblocks');
      expect(
        tbSection,
        isNot(contains('allow read, write: if request.auth != null;')),
        reason: 'Timeblocks should not have broad auth-only access',
      );
    });
  });
}

/// Extracts a rough section of the rules file around a keyword.
String _extractSection(String content, String keyword) {
  final idx = content.indexOf(keyword);
  if (idx == -1) return '';
  final start = (idx - 100).clamp(0, content.length);
  final end = (idx + 300).clamp(0, content.length);
  return content.substring(start, end);
}
