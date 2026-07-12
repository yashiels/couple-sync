import 'dart:async';
import 'dart:convert';

import 'package:couple_sync/core/overlap/overlap_controller.dart';
import 'package:couple_sync/core/overlap/overlap_engine.dart';
import 'package:couple_sync/core/models/time_block.dart';
import 'package:couple_sync/services/providers/auth_state_provider.dart';
import 'package:couple_sync/services/providers/sync_provider.dart';
import 'package:couple_sync/services/sync_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  test('floorToHour rounds down to the hour', () {
    const ms = 1704067200000; // 2024-01-01T00:00:00Z
    expect(floorToHour(ms + 59 * 60 * 1000), ms);
  });

  test('floorToHour floors to hour boundary across day', () {
    // 2024-01-01T23:59:59Z -> 2024-01-01T23:00:00Z
    const base = 1704067200000;
    const hourBeforeMidnight = base + 23 * 60 * 60 * 1000;
    expect(
      floorToHour(base + 23 * 60 * 60 * 1000 + 59 * 1000),
      hourBeforeMidnight,
    );
  });

  test('computeOverlapInputHash is deterministic for identical inputs', () {
    final h1 = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    final h2 = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    expect(h1, h2);
  });

  test('inputHash changes when a pref changes', () {
    final base = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    final toggled = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: true),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    expect(base, isNot(toggled));
  });

  test('inputHash changes when nowBucket changes', () {
    final h1 = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    final h2 = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000 + 60 * 60 * 1000,
    );
    expect(h1, isNot(h2));
  });

  test('inputHash is order-independent within each partner list', () {
    final a = TimeBlock(
      userId: 'u',
      title: 'a',
      type: TimeBlockType.busy,
      category: TimeBlockCategory.other,
      startUtc: 1000,
      endUtc: 2000,
      timezone: 'UTC',
      source: TimeBlockSource.manual,
      visibility: TimeBlockVisibility.bothPartners,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    final b = TimeBlock(
      userId: 'u',
      title: 'b',
      type: TimeBlockType.busy,
      category: TimeBlockCategory.other,
      startUtc: 3000,
      endUtc: 4000,
      timezone: 'UTC',
      source: TimeBlockSource.manual,
      visibility: TimeBlockVisibility.bothPartners,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    final h1 = computeOverlapInputHash(
      blocksA: [a, b],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    final h2 = computeOverlapInputHash(
      blocksA: [b, a],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    expect(h1, h2);
  });

  test('computeOverlapInputHash does not mutate caller block lists', () {
    final a = TimeBlock(
      userId: 'u',
      title: 'a',
      type: TimeBlockType.busy,
      category: TimeBlockCategory.other,
      startUtc: 3000,
      endUtc: 4000,
      timezone: 'UTC',
      source: TimeBlockSource.manual,
      visibility: TimeBlockVisibility.bothPartners,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    final b = TimeBlock(
      userId: 'u',
      title: 'b',
      type: TimeBlockType.busy,
      category: TimeBlockCategory.other,
      startUtc: 1000,
      endUtc: 2000,
      timezone: 'UTC',
      source: TimeBlockSource.manual,
      visibility: TimeBlockVisibility.bothPartners,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    final list = [a, b];
    computeOverlapInputHash(
      blocksA: list,
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    expect(list[0], same(a));
    expect(list[1], same(b));
  });

  test('inputHash is 16 hex characters', () {
    final h = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(h), isTrue);
  });

  // -------------------------------------------------------------------------
  // Regression: user:update WS event must force a partner profile refetch.
  //
  // Before the fix, `_resolveCoupleAndProfiles` early-returned when the
  // couple's two uids were unchanged — which is exactly the case for a
  // `user:update` event (the partner's profile changed, couple membership
  // did not). So the profile refetch was wrongly skipped. This test feeds a
  // `user:update` event after the couple is already resolved and asserts the
  // partner profile HTTP endpoint was hit again.
  // -------------------------------------------------------------------------

  group('OverlapController user:update profile refetch', () {
    late int userACalls;
    late _FakeWsFactory wsFactory;
    late SyncService service;
    late ProviderContainer container;

    setUp(() {
      tz_data.initializeTimeZones();
      userACalls = 0;
      wsFactory = _FakeWsFactory();
      final client = MockClient((http.Request request) async {
        final path = request.url.path;
        if (request.method == 'GET' &&
            path.endsWith('/couples/couple-1')) {
          return _jsonResponse(200, {
            'userAUid': 'uA',
            'userBUid': 'uB',
            'status': 'active',
            'pairedAt': 1000,
            'unpairHistory': <Map<String, dynamic>>[],
            'createdAt': 1000,
          });
        }
        if (request.method == 'GET' && path.endsWith('/users/uA')) {
          userACalls++;
          return _jsonResponse(200, {
            'email': 'a@b.com',
            'timezone':
                userACalls == 1 ? 'UTC' : 'America/New_York',
            'fcmTokens': <String>[],
            'createdAt': 1000,
            'showLateNightWindows': false,
          });
        }
        if (request.method == 'GET' && path.endsWith('/users/uB')) {
          return _jsonResponse(200, {
            'email': 'b@b.com',
            'timezone': 'UTC',
            'fcmTokens': <String>[],
            'createdAt': 1000,
            'showLateNightWindows': false,
          });
        }
        return _jsonResponse(404, {'error': 'not found'});
      });

      service = SyncService(
        baseUrl: 'https://api.test',
        wsUrl: 'wss://api.test/sync',
        tokenProvider: () async => 'tok',
        httpClient: client,
        wsConnect: wsFactory.asFactory(),
        cache: _FakeBlockCache(),
        backoffFor: (_) => Duration.zero,
      );

      container = ProviderContainer(overrides: [
        syncServiceProvider.overrideWithValue(service),
        currentUserIdProvider.overrideWithValue('uA'),
      ]);
    });

    tearDown(() {
      container.dispose();
      service.dispose();
    });

    test('user:update re-fetches partner profile when couple uids are stable',
        () async {
      // Keep the provider alive.
      final sub = container.listen(
        overlapControllerProvider('couple-1'),
        (_, _) {},
      );

      // Wait for initial couple + profile resolve + debounce compute.
      await Future<void>.delayed(
        const Duration(milliseconds: 700),
      );
      expect(userACalls, 1, reason: 'initial profile fetch');

      // The WS connected during the delay; grab the live socket from the
      // persisted list (broadcast streams don't replay past events).
      expect(wsFactory.created, isNotEmpty);
      final socket = wsFactory.created.first;
      await Future<void>.delayed(Duration.zero);

      // Server pushes user:update — partner changed their timezone.
      socket.inject(jsonEncode({'t': 'user:update', 'uid': 'uB'}));

      // Wait for re-resolve + debounce compute.
      await Future<void>.delayed(
        const Duration(milliseconds: 700),
      );

      expect(
        userACalls,
        greaterThanOrEqualTo(2),
        reason:
            'user:update must force a profile refetch even when couple uids '
            'are unchanged',
      );

      sub.close();
    });
  });
}

// ---------------------------------------------------------------------------
// Minimal fakes (mirrors of sync_service_test helpers).
// ---------------------------------------------------------------------------

http.Response _jsonResponse(int status, Map<String, dynamic> body) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

class _FakeBlockCache implements BlockCache {
  final Map<String, List<TimeBlock>> _store = {};

  @override
  List<TimeBlock> getBlocks(String coupleId) =>
      _store[coupleId]?.toList() ?? const [];

  @override
  Future<void> putBlock(String coupleId, TimeBlock block) async {
    final blocks = _store.putIfAbsent(coupleId, () => []).toList();
    final idx = blocks.indexWhere((b) => b.id == block.id);
    if (idx >= 0) {
      blocks[idx] = block;
    } else {
      blocks.add(block);
    }
    _store[coupleId] = blocks;
  }

  @override
  Future<void> deleteBlock(String coupleId, String blockId) async {
    final blocks = _store[coupleId];
    if (blocks == null) return;
    _store[coupleId] = blocks.where((b) => b.id != blockId).toList();
  }

  @override
  Future<void> replaceAll(String coupleId, List<TimeBlock> blocks) async {
    _store[coupleId] = blocks.toList();
  }
}

class _FakeWsConnection implements WsConnection {
  final StreamController<String> _incoming =
      StreamController<String>.broadcast();
  final List<String> sent = [];
  bool _closed = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String data) {
    if (_closed) return;
    sent.add(data);
  }

  @override
  void close() {
    _closed = true;
    _incoming.close();
  }

  @override
  bool get isClosed => _closed;

  void inject(String raw) => _incoming.add(raw);
}

class _FakeWsFactory {
  final List<_FakeWsConnection> created = [];
  final StreamController<_FakeWsConnection> _onCreate =
      StreamController<_FakeWsConnection>.broadcast();

  Stream<_FakeWsConnection> get onCreate => _onCreate.stream;

  Future<WsConnection> Function(Uri uri) asFactory() {
    return (Uri uri) async {
      final conn = _FakeWsConnection();
      created.add(conn);
      _onCreate.add(conn);
      return conn;
    };
  }
}
