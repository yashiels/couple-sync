import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;

import '../../../shared/models/time_block_model.dart';

/// Provides Google Calendar integration via OAuth 2.0 + CalendarApi freebusy.
class GoogleCalendarService {
  static const _scopes = [
    gcal.CalendarApi.calendarReadonlyScope,
    gcal.CalendarApi.calendarEventsScope,
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);
  final FirebaseFirestore _firestore;

  GoogleCalendarService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Connection ────────────────────────────────────────────────────────────

  /// Whether the user is currently signed in to Google Calendar.
  bool get isConnected => _googleSignIn.currentUser != null;

  /// The email address of the connected Google account, or `null` if not connected.
  String? get connectedEmail => _googleSignIn.currentUser?.email;

  /// Initiates Google OAuth and returns the connected email, or null if cancelled.
  Future<String?> connectAccount() async {
    try {
      final account = await _googleSignIn.signIn();
      return account?.email;
    } catch (e) {
      debugPrint('GoogleCalendarService.connectAccount error: $e');
      return null;
    }
  }

  /// Revokes tokens and signs out.
  Future<void> disconnect() async {
    await _googleSignIn.disconnect();
  }

  /// Attempts a silent re-authentication using a previously stored account.
  Future<bool> trySilentSignIn() async {
    try {
      final account = await _googleSignIn.signInSilently();
      return account != null;
    } catch (_) {
      return false;
    }
  }

  // ── Freebusy fetch ────────────────────────────────────────────────────────

  /// Fetches busy periods for the next [days] days from the primary calendar.
  /// Converts each busy slot to a [TimeBlock] with source = google.
  Future<List<TimeBlock>> fetchBusyPeriods({
    required String userId,
    required String coupleId,
    int days = 14,
  }) async {
    final account = _googleSignIn.currentUser ??
        await _googleSignIn.signInSilently();
    if (account == null) throw Exception('Not signed in to Google Calendar');

    final authHeaders = await account.authHeaders;
    final client = _AuthClient(authHeaders);

    try {
      final calendarApi = gcal.CalendarApi(client);

      final now = DateTime.now().toUtc();
      final until = now.add(Duration(days: days));

      final response = await calendarApi.freebusy.query(
        gcal.FreeBusyRequest(
          timeMin: now,
          timeMax: until,
          items: [gcal.FreeBusyRequestItem(id: 'primary')],
        ),
      );

      final primaryCal = response.calendars?['primary'];
      if (primaryCal == null) return [];

      return (primaryCal.busy ?? []).map((period) {
        return TimeBlock(
          id: '',
          userId: userId,
          coupleId: coupleId,
          title: 'Busy',
          startUtc: period.start!.toUtc(),
          endUtc: period.end!.toUtc(),
          type: BlockType.busy,
          timezone: 'UTC',
          source: BlockSource.google,
          visibility: TimeBlockVisibility.bothPartners,
          category: BlockCategory.other,
          createdAt: DateTime.now().toUtc(),
        );
      }).toList();
    } finally {
      client.close();
    }
  }

  // ── Firestore sync ────────────────────────────────────────────────────────

  /// Fetches busy periods and writes them to Firestore, replacing any
  /// previously synced Google blocks for this user.
  /// If [connectionId] is provided, updates that specific connection's lastSync.
  Future<void> syncToFirestore({
    required String userId,
    required String coupleId,
    String? connectionId,
  }) async {
    final blocks = await fetchBusyPeriods(userId: userId, coupleId: coupleId);

    final blocksRef = _firestore
        .collection('timeblocks')
        .doc(coupleId)
        .collection('blocks');

    final batch = _firestore.batch();

    // Delete stale Google blocks for this user.
    final stale = await blocksRef
        .where('ownerUid', isEqualTo: userId)
        .where('source', isEqualTo: 'google')
        .get();
    for (final doc in stale.docs) {
      batch.delete(doc.reference);
    }

    // Write fresh blocks.
    for (final block in blocks) {
      batch.set(blocksRef.doc(), block.toFirestore());
    }

    await batch.commit();

    if (connectionId != null) {
      await _updateConnectionLastSync(userId, connectionId);
    }
  }

  // ── Meet event creation ───────────────────────────────────────────────────

  /// Creates a Google Calendar event with an auto-generated Google Meet link.
  /// Returns the Meet link URL, or null if creation failed.
  Future<String?> createMeetEvent({
    required String title,
    required DateTime startUtc,
    required DateTime endUtc,
    required String timezone,
    String? partnerEmail,
  }) async {
    final account = _googleSignIn.currentUser ??
        await _googleSignIn.signInSilently();
    if (account == null) throw Exception('Not signed in to Google Calendar');

    final authHeaders = await account.authHeaders;
    final client = _AuthClient(authHeaders);

    try {
      final calendarApi = gcal.CalendarApi(client);

      final event = gcal.Event(
        summary: title,
        start: gcal.EventDateTime(dateTime: startUtc, timeZone: timezone),
        end: gcal.EventDateTime(dateTime: endUtc, timeZone: timezone),
        conferenceData: gcal.ConferenceData(
          createRequest: gcal.CreateConferenceRequest(
            requestId: DateTime.now().millisecondsSinceEpoch.toString(),
            conferenceSolutionKey:
                gcal.ConferenceSolutionKey(type: 'hangoutsMeet'),
          ),
        ),
        attendees: partnerEmail != null
            ? [gcal.EventAttendee(email: partnerEmail)]
            : null,
      );

      final created = await calendarApi.events.insert(
        event,
        'primary',
        conferenceDataVersion: 1,
      );

      return created.conferenceData?.entryPoints
          ?.firstWhere(
            (e) => e.entryPointType == 'video',
            orElse: () => gcal.EntryPoint(),
          )
          .uri;
    } finally {
      client.close();
    }
  }

  /// Updates a specific connection's lastSync in the calendarConnections array.
  Future<void> _updateConnectionLastSync(
      String userId, String connectionId) async {
    final userRef = _firestore.collection('users').doc(userId);
    final doc = await userRef.get();
    if (!doc.exists) return;

    final connections =
        (doc.data()?['calendarConnections'] as List<dynamic>?) ?? [];
    final updated = connections.map((c) {
      final map = Map<String, dynamic>.from(c as Map);
      if (map['id'] == connectionId) {
        map['lastSync'] = Timestamp.now();
      }
      return map;
    }).toList();

    await userRef.update({'calendarConnections': updated});
  }
}

/// Minimal HTTP client that injects Google OAuth headers on every request.
class _AuthClient extends http.BaseClient {
  _AuthClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
