import 'dart:async';
import 'dart:convert';

import 'package:couple_sync/core/models/models.dart';
import 'package:couple_sync/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// In-memory [BlockCache] — no Hive init required.
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

/// A controllable fake [WsConnection]. Tests push messages via [inject] and
/// simulate drops via [simulateDrop].
class _FakeWsConnection implements WsConnection {
  final StreamController<String> _incoming = StreamController<String>.broadcast();
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

  /// Push a raw JSON message as if the server sent it.
  void inject(String raw) => _incoming.add(raw);

  /// Simulate the socket dropping. Reconnect logic should kick in.
  void simulateDrop() {
    _incoming.addError(Exception('connection dropped'));
  }
}

/// Factory that hands out fake connections so the test can drive them.
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

TimeBlock _block({
  String id = 'b1',
  String userId = 'u1',
  String title = 'Work',
  int startUtc = 1000,
  int endUtc = 2000,
}) {
  return TimeBlock(
    id: id,
    userId: userId,
    title: title,
    type: TimeBlockType.busy,
    category: TimeBlockCategory.work,
    startUtc: startUtc,
    endUtc: endUtc,
    timezone: 'UTC',
    source: TimeBlockSource.manual,
    visibility: TimeBlockVisibility.bothPartners,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
  );
}

http.Response _jsonResponse(int status, Map<String, dynamic> body) {
  return http.Response(jsonEncode(body), status,
      headers: {'content-type': 'application/json'});
}

void main() {
  group('SyncService HTTP', () {
    late SyncService service;
    late List<http.Request> requests;

    setUp(() {
      requests = [];
      final client = MockClient((http.Request request) async {
        requests.add(request);
        // POST /auth/verify → 200
        if (request.url.path.endsWith('/auth/verify')) {
          return _jsonResponse(200, {'ok': true});
        }
        // POST /auth/fcm-token → 200
        if (request.url.path.endsWith('/auth/fcm-token')) {
          return _jsonResponse(200, {'ok': true});
        }
        // POST /blocks → 201 with id
        if (request.method == 'POST' && request.url.path.endsWith('/blocks')) {
          return _jsonResponse(201, {'id': 'new-block-id'});
        }
        // POST /blocks/batch
        if (request.url.path.endsWith('/blocks/batch')) {
          return _jsonResponse(200, {'deletedCount': 3, 'createdCount': 2});
        }
        // POST /invites
        if (request.method == 'POST' && request.url.path.endsWith('/invites')) {
          return _jsonResponse(201, {'code': 'ABC123'});
        }
        // POST /invites/:code/redeem
        if (request.url.path.contains('/redeem')) {
          return _jsonResponse(200, {'coupleId': 'couple-1'});
        }
        // POST /couples/:id/unpair
        if (request.url.path.contains('/unpair')) {
          return _jsonResponse(200, {'ok': true});
        }
        // GET /users/me
        if (request.method == 'GET' && request.url.path.endsWith('/users/me')) {
          return _jsonResponse(200, {
            'email': 'a@b.com',
            'displayName': 'A',
            'timezone': 'UTC',
            'fcmTokens': <String>[],
            'createdAt': 1000,
            'showLateNightWindows': false,
          });
        }
        // GET /overlaps/latest
        if (request.url.path.contains('/overlaps/latest')) {
          return _jsonResponse(200, {
            'windows': <Map<String, dynamic>>[],
            'computedAt': 1000,
            'inputHash': 'hash1',
            'computedBy': 'u1',
          });
        }
        return _jsonResponse(404, {'error': 'not found'});
      });

      service = SyncService(
        baseUrl: 'https://api.test',
        wsUrl: 'wss://api.test/sync',
        tokenProvider: () async => 'test-token',
        httpClient: client,
        wsConnect: (Uri uri) async => _FakeWsConnection(),
        cache: _FakeBlockCache(),
        backoffFor: (_) => Duration.zero,
      );
    });

    tearDown(() => service.dispose());

    test('upsertUser POSTs to /auth/verify with Bearer token', () async {
      await service.upsertUser(UserModel(
        email: 'a@b.com',
        displayName: 'A',
        timezone: 'UTC',
        fcmTokens: const [],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      ));
      final req = requests.singleWhere(
          (r) => r.url.path.endsWith('/auth/verify'));
      expect(req.method, 'POST');
      expect(req.headers['authorization'], 'Bearer test-token');
      expect(jsonDecode(req.body)['email'], 'a@b.com');
    });

    test('registerFcmToken POSTs the token to /auth/fcm-token', () async {
      await service.registerFcmToken('fcm-xyz');
      final req = requests.singleWhere(
          (r) => r.url.path.endsWith('/auth/fcm-token'));
      expect(jsonDecode(req.body)['token'], 'fcm-xyz');
    });

    test('createBlock returns the server-generated id', () async {
      final id = await service.createBlock('c1', _block());
      expect(id, 'new-block-id');
    });

    test('atomicReplaceGoogleSourcedBlocks returns counts from server', () async {
      final result = await service.atomicReplaceGoogleSourcedBlocks(
        'c1', 'u1', [_block(id: 'g1'), _block(id: 'g2')],
      );
      expect(result.deletedCount, 3);
      expect(result.createdCount, 2);
    });

    test('createInvite returns the invite code', () async {
      final code = await service.createInvite('u1');
      expect(code, 'ABC123');
    });

    test('redeemInvite returns the coupleId', () async {
      final coupleId = await service.redeemInvite('ABC123');
      expect(coupleId, 'couple-1');
    });

    test('unpair calls POST /couples/:id/unpair', () async {
      await service.unpair('c1');
      final req = requests.singleWhere(
          (r) => r.url.path.contains('/unpair'));
      expect(req.method, 'POST');
    });

    test('getUser returns null on 404', () async {
      // Override the client to return 404 for /users/me.
      final client404 = MockClient((_) async => http.Response('', 404));
      final s = SyncService(
        baseUrl: 'https://api.test',
        wsUrl: 'wss://api.test/sync',
        tokenProvider: () async => 't',
        httpClient: client404,
        cache: _FakeBlockCache(),
        backoffFor: (_) => Duration.zero,
      );
      addTearDown(s.dispose);
      expect(await s.getUser('u1'), isNull);
    });

    test('getOverlap parses the latest overlap', () async {
      final result = await service.getOverlap('c1');
      expect(result, isNotNull);
      expect(result!.inputHash, 'hash1');
      expect(result.computedBy, 'u1');
    });
  });

  group('SyncService WS — watchBlocks', () {
    late SyncService service;
    late _FakeWsFactory wsFactory;
    late _FakeBlockCache cache;

    setUp(() {
      wsFactory = _FakeWsFactory();
      cache = _FakeBlockCache();
      service = SyncService(
        baseUrl: 'https://api.test',
        wsUrl: 'wss://api.test/sync',
        tokenProvider: () async => 'tok',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        wsConnect: wsFactory.asFactory(),
        cache: cache,
        backoffFor: (_) => Duration.zero,
      );
    });

    tearDown(() => service.dispose());

    test('seeds from cache then emits on block:set', () async {
      // Pre-seed the cache.
      await cache.replaceAll('c1', [_block(id: 'cached', userId: 'u1')]);

      final emitted = <List<TimeBlock>>[];
      final sub = service.watchBlocks('c1').listen(emitted.add);

      // Wait for the WS to connect.
      final socket = await wsFactory.onCreate.first;

      // First emission: the cached block.
      await Future<void>.delayed(Duration.zero);
      expect(emitted.first.single.id, 'cached');

      // Server pushes a new block.
      socket.inject(jsonEncode({
        't': 'block:set',
        'block': {
          ..._block(id: 'new', userId: 'u1').toJson(),
          'id': 'new',
          'createdAt': 1000,
        },
      }));
      await Future<void>.delayed(Duration.zero);

      expect(emitted.last.length, 2);
      expect(emitted.last.any((b) => b.id == 'new'), isTrue);
      // Cache was updated.
      expect(cache.getBlocks('c1').any((b) => b.id == 'new'), isTrue);

      // block:del removes it.
      socket.inject(jsonEncode({'t': 'block:del', 'id': 'new'}));
      await Future<void>.delayed(Duration.zero);
      expect(emitted.last.any((b) => b.id == 'new'), isFalse);
      expect(cache.getBlocks('c1').any((b) => b.id == 'new'), isFalse);

      await sub.cancel();
    });

    test('reconnects with backoff after a drop', () async {
      service.watchBlocks('c1');
      final socket1 = await wsFactory.onCreate.first;
      // Wait for the sub message to be sent.
      await Future<void>.delayed(Duration.zero);
      expect(socket1.sent.any((s) => s.contains('"sub"')), isTrue);

      // Drop the socket; a new one should be created (backoff is Duration.zero).
      socket1.simulateDrop();
      final socket2 = await wsFactory.onCreate.first;
      expect(socket2, isNot(same(socket1)));
      // The new socket also subscribes.
      await Future<void>.delayed(Duration.zero);
      expect(socket2.sent.any((s) => s.contains('"sub"')), isTrue);
    });
  });

  group('SyncService WS — publishOverlap', () {
    test('encodes the overlap message with windows, inputHash, computedBy',
        () async {
      final wsFactory = _FakeWsFactory();
      final service = SyncService(
        baseUrl: 'https://api.test',
        wsUrl: 'wss://api.test/sync',
        tokenProvider: () async => 'tok',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        wsConnect: wsFactory.asFactory(),
        cache: _FakeBlockCache(),
        backoffFor: (_) => Duration.zero,
      );
      addTearDown(service.dispose);

      // Open the session by watching overlap (which opens the WS).
      service.watchOverlap('c1');
      final socket = await wsFactory.onCreate.first;
      await Future<void>.delayed(Duration.zero);

      final result = OverlapResult(
        windows: [
          OverlapWindow(
              startUtc: 100,
              endUtc: 200,
              durationMinutes: 1,
              score: 0.5,
              reasonableBoth: true),
        ],
        computedAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        inputHash: 'abc123',
        computedBy: 'u1',
      );
      await service.publishOverlap('c1', result);

      // Find the overlap message among sent frames.
      final overlapFrame = socket.sent
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .firstWhere((m) => m['t'] == 'overlap');
      expect(overlapFrame['t'], 'overlap');
      expect(overlapFrame['inputHash'], 'abc123');
      expect(overlapFrame['computedBy'], 'u1');
      final windows = overlapFrame['windows'] as List<dynamic>;
      expect(windows.length, 1);
      expect(windows.single['startUtc'], 100);
    });
  });
}
