import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../shared/models/time_block_model.dart';

/// Provides Microsoft Calendar integration via OAuth 2.0 PKCE + Graph API.
///
/// Uses [FlutterAppAuth] for the OAuth 2.0 authorization code flow with PKCE,
/// and [FlutterSecureStorage] to persist access and refresh tokens securely.
/// Calendar events are fetched from the Microsoft Graph `calendarView` endpoint
/// and mapped to [TimeBlock] instances for display and Firestore persistence.
class MicrosoftCalendarService {
  // TODO: Set from environment/config
  static const _clientId = 'YOUR_MS_CLIENT_ID';
  static const _redirectUri = 'com.coupleschedule.app://oauth2redirect';
  static const _authority = 'https://login.microsoftonline.com/common';
  static const _scopes = ['Calendars.Read', 'User.Read', 'offline_access'];

  final FlutterAppAuth _appAuth;
  final FlutterSecureStorage _secureStorage;
  final FirebaseFirestore _firestore;

  bool _isConnected = false;
  String? _connectedEmail;

  /// Creates a [MicrosoftCalendarService].
  ///
  /// All parameters are optional and default to production instances.
  MicrosoftCalendarService({
    FlutterAppAuth? appAuth,
    FlutterSecureStorage? secureStorage,
    FirebaseFirestore? firestore,
  })  : _appAuth = appAuth ?? const FlutterAppAuth(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _firestore = firestore ?? FirebaseFirestore.instance;

  /// Whether the user is currently connected to Microsoft Calendar.
  bool get isConnected => _isConnected;

  /// The email address of the connected Microsoft account, or `null`.
  String? get connectedEmail => _connectedEmail;

  /// Initiates the Microsoft OAuth 2.0 PKCE authorization flow.
  ///
  /// Returns `true` when the user successfully grants access, `false` if the
  /// flow is cancelled or fails.
  Future<bool> connect() async {
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _clientId,
          _redirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: '$_authority/oauth2/v2.0/authorize',
            tokenEndpoint: '$_authority/oauth2/v2.0/token',
          ),
          scopes: _scopes,
        ),
      );

      final accessToken = result.accessToken;
      if (accessToken == null) return false;

      await _secureStorage.write(key: 'ms_access_token', value: accessToken);
      await _secureStorage.write(
        key: 'ms_refresh_token',
        value: result.refreshToken,
      );

      _connectedEmail = await _fetchUserEmail(accessToken);
      _isConnected = true;
      return true;
    } catch (e) {
      debugPrint('MicrosoftCalendarService.connect error: $e');
      return false;
    }
  }

  /// Disconnects by clearing stored tokens.
  Future<void> disconnect() async {
    await _secureStorage.delete(key: 'ms_access_token');
    await _secureStorage.delete(key: 'ms_refresh_token');
    _isConnected = false;
    _connectedEmail = null;
  }

  /// Tries to restore a previous session from stored refresh tokens.
  ///
  /// Returns `true` when a valid session is restored, `false` otherwise.
  Future<bool> tryRestoreSession() async {
    final refreshToken = await _secureStorage.read(key: 'ms_refresh_token');
    if (refreshToken == null) return false;

    try {
      final result = await _appAuth.token(
        TokenRequest(
          _clientId,
          _redirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: '$_authority/oauth2/v2.0/authorize',
            tokenEndpoint: '$_authority/oauth2/v2.0/token',
          ),
          refreshToken: refreshToken,
          scopes: _scopes,
        ),
      );

      final accessToken = result.accessToken;
      if (accessToken == null) return false;

      await _secureStorage.write(key: 'ms_access_token', value: accessToken);
      if (result.refreshToken != null) {
        await _secureStorage.write(
          key: 'ms_refresh_token',
          value: result.refreshToken,
        );
      }

      _connectedEmail = await _fetchUserEmail(accessToken);
      _isConnected = true;
      return true;
    } catch (e) {
      debugPrint('MicrosoftCalendarService.tryRestoreSession error: $e');
      return false;
    }
  }

  /// Fetches busy periods from Microsoft Calendar for the next [days] days.
  ///
  /// Uses the Graph API `calendarView` endpoint and filters out events whose
  /// `showAs` status is `free`. Each non-free event is mapped to a [TimeBlock]
  /// with [BlockSource.microsoft].
  Future<List<TimeBlock>> fetchBusyPeriods({
    required String userId,
    required String coupleId,
    int days = 14,
  }) async {
    final accessToken = await _getValidAccessToken();
    if (accessToken == null) {
      throw Exception('Not signed in to Microsoft');
    }

    final now = DateTime.now().toUtc();
    final until = now.add(Duration(days: days));

    final uri = Uri.parse(
      'https://graph.microsoft.com/v1.0/me/calendarView'
      '?startDateTime=${now.toIso8601String()}'
      '&endDateTime=${until.toIso8601String()}'
      r'&$select=start,end,subject,showAs'
      r'&$top=250',
    );

    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $accessToken',
      'Prefer': 'outlook.timezone="UTC"',
    });

    if (response.statusCode != 200) {
      throw Exception('Microsoft Graph API error: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final events = (data['value'] as List<dynamic>?) ?? [];

    return events
        .where((e) => e['showAs'] != 'free')
        .map((e) {
      final start =
          DateTime.parse(e['start']['dateTime'] as String).toUtc();
      final end =
          DateTime.parse(e['end']['dateTime'] as String).toUtc();

      return TimeBlock(
        id: '',
        userId: userId,
        coupleId: coupleId,
        type: BlockType.busy,
        title: 'Busy',
        startUtc: start,
        endUtc: end,
        timezone: 'UTC',
        source: BlockSource.microsoft,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.other,
        createdAt: DateTime.now().toUtc(),
      );
    }).toList();
  }

  /// Syncs Microsoft calendar events to Firestore.
  ///
  /// Fetches busy periods and writes them to Firestore, replacing any
  /// previously synced Microsoft blocks for this user.
  Future<void> syncToFirestore({
    required String userId,
    required String coupleId,
  }) async {
    final blocks = await fetchBusyPeriods(userId: userId, coupleId: coupleId);

    final blocksRef = _firestore
        .collection('timeblocks')
        .doc(coupleId)
        .collection('blocks');

    // Remove stale Microsoft blocks for this user.
    final stale = await blocksRef
        .where('userId', isEqualTo: userId)
        .where('source', isEqualTo: BlockSource.microsoft.name)
        .get();

    // Firestore batches max 500 ops. Chunk into 400 for safety.
    final allOps = <_BatchOp>[
      ...stale.docs.map((d) => _BatchOp.delete(d.reference)),
      ...blocks.map((b) => _BatchOp.set(blocksRef.doc(), b.toFirestore())),
    ];

    for (var i = 0; i < allOps.length; i += 400) {
      final chunk = allOps.sublist(i, (i + 400).clamp(0, allOps.length));
      final batch = _firestore.batch();
      for (final op in chunk) {
        if (op.isDelete) {
          batch.delete(op.ref!);
        } else {
          batch.set(op.ref!, op.data!);
        }
      }
      await batch.commit();
    }
  }

  /// Returns a valid access token, refreshing if necessary.
  Future<String?> _getValidAccessToken() async {
    var token = await _secureStorage.read(key: 'ms_access_token');
    if (token == null) {
      final restored = await tryRestoreSession();
      if (!restored) return null;
      token = await _secureStorage.read(key: 'ms_access_token');
    }
    return token;
  }

  /// Fetches the user's email address from the Microsoft Graph /me endpoint.
  Future<String?> _fetchUserEmail(String accessToken) async {
    final response = await http.get(
      Uri.parse(
        r'https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName',
      ),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return (data['mail'] as String?) ??
          (data['userPrincipalName'] as String?);
    }
    return null;
  }
}

/// Internal helper to represent a Firestore batch operation uniformly.
class _BatchOp {
  _BatchOp.delete(this.ref)
      : data = null,
        isDelete = true;

  _BatchOp.set(this.ref, this.data) : isDelete = false;

  final DocumentReference? ref;
  final Map<String, dynamic>? data;
  final bool isDelete;
}
