import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/models/models.dart';

/// Exception thrown by [SyncService] for HTTP/WS/cache failures. Mirrors the
/// surface of [FirestoreException] so callers can swap implementations without
/// changing catch blocks.
class SyncException implements Exception {
  final String code;
  final String message;
  final int? statusCode;
  final dynamic originalError;

  const SyncException({
    required this.code,
    required this.message,
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() => 'SyncException($code): $message';
}

// ---------------------------------------------------------------------------
// WS connection abstraction
// ---------------------------------------------------------------------------

/// A thin bidirectional text-channel abstraction over a WebSocket. Decouples
/// [SyncService] from `package:web_socket_channel`'s concrete `WebSocketChannel`
/// so unit tests can drive a fake connection.
abstract class WsConnection {
  Stream<String> get messages;
  void send(String data);
  void close();
  bool get isClosed;
}

class _RealWsConnection implements WsConnection {
  final WebSocketChannel _channel;
  _RealWsConnection(this._channel);

  @override
  Stream<String> get messages => _channel.stream.cast<String>();

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  void close() => _channel.sink.close();

  @override
  bool get isClosed => _channel.closeCode != null;
}

/// Factory signature used to open a [WsConnection] for a given [uri].
typedef WsConnectionFactory = Future<WsConnection> Function(Uri uri);

Future<WsConnection> _defaultWsConnect(Uri uri) async {
  final channel = WebSocketChannel.connect(uri);
  return _RealWsConnection(channel);
}

// ---------------------------------------------------------------------------
// Offline block cache abstraction
// ---------------------------------------------------------------------------

/// A key-value block cache keyed by coupleId. The default [HiveBlockCache]
/// persists to disk; tests inject an in-memory [FakeBlockCache] (in the test
/// file) to avoid Hive initialization.
abstract class BlockCache {
  List<TimeBlock> getBlocks(String coupleId);
  Future<void> putBlock(String coupleId, TimeBlock block);
  Future<void> deleteBlock(String coupleId, String blockId);
  Future<void> replaceAll(String coupleId, List<TimeBlock> blocks);
}

/// Hive-backed [BlockCache]. Stores the block list as a single JSON string per
/// coupleId under key `blocks:<coupleId>`. Lazily opens the box on first write;
/// reads return an empty list when the box is not yet open (cold start before
/// Hive has been initialised will simply render no cached blocks — the WS seeds
/// the live list immediately after connect).
class HiveBlockCache implements BlockCache {
  // Hive Box type is dynamic; kept as `dynamic` to avoid importing hive here
  // transitively in a way that couples the type. We only call getString/put.
  final Future<dynamic> Function()? _boxOpener;
  dynamic _box;

  HiveBlockCache({Future<dynamic> Function()? boxOpener})
      : _boxOpener = boxOpener;

  Future<dynamic> _ensureBox() async {
    if (_box != null) return _box;
    if (_boxOpener != null) {
      _box = await _boxOpener();
    }
    return _box;
  }

  String _key(String coupleId) => 'blocks:$coupleId';

  @override
  List<TimeBlock> getBlocks(String coupleId) {
    final box = _box;
    if (box == null) return const [];
    try {
      final raw = box.get(_key(coupleId));
      if (raw is! String || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return TimeBlock.fromJson(m, m['id'] as String? ?? '');
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> putBlock(String coupleId, TimeBlock block) async {
    await _ensureBox();
    final box = _box;
    if (box == null) return;
    final blocks = getBlocks(coupleId).toList();
    final idx = blocks.indexWhere((b) => b.id == block.id);
    if (idx >= 0) {
      blocks[idx] = block;
    } else {
      blocks.add(block);
    }
    await box.put(_key(coupleId), jsonEncode(blocks.map(_blockToJsonWithId).toList()));
  }

  @override
  Future<void> deleteBlock(String coupleId, String blockId) async {
    await _ensureBox();
    final box = _box;
    if (box == null) return;
    final blocks = getBlocks(coupleId).where((b) => b.id != blockId).toList();
    await box.put(_key(coupleId), jsonEncode(blocks.map(_blockToJsonWithId).toList()));
  }

  @override
  Future<void> replaceAll(String coupleId, List<TimeBlock> blocks) async {
    await _ensureBox();
    final box = _box;
    if (box == null) return;
    await box.put(_key(coupleId), jsonEncode(blocks.map(_blockToJsonWithId).toList()));
  }
}

// ---------------------------------------------------------------------------
// JSON helpers (models use Firestore Timestamp in toJson; the backend expects
// int ms since epoch. These helpers produce JSON-serialisable maps without
// touching the model classes.)
// ---------------------------------------------------------------------------

Map<String, dynamic> _blockToJsonWithId(TimeBlock b) => {
      ...b.toJson(),
      'id': b.id,
      'createdAt': b.createdAt.millisecondsSinceEpoch,
    };

Map<String, dynamic> _blockToJson(TimeBlock b) => {
      ...b.toJson(),
      'createdAt': b.createdAt.millisecondsSinceEpoch,
    };

// ---------------------------------------------------------------------------
// Per-couple WS session
// ---------------------------------------------------------------------------

class _CoupleSession {
  final String coupleId;
  final SyncService _service;
  final BlockCache _cache;
  final WsConnectionFactory _wsConnect;
  final Duration Function(int attempt) _backoffFor;

  final StreamController<List<TimeBlock>> _blocksController =
      StreamController<List<TimeBlock>>.broadcast();
  final StreamController<OverlapResult?> _overlapController =
      StreamController<OverlapResult?>.broadcast();

  Stream<List<TimeBlock>> get blocks => _blocksController.stream;
  Stream<OverlapResult?> get overlap => _overlapController.stream;

  WsConnection? _socket;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _disposed = false;
  List<TimeBlock> _blocks = const [];

  _CoupleSession({
    required this.coupleId,
    required SyncService service,
    required BlockCache cache,
    required WsConnectionFactory wsConnect,
    required Duration Function(int attempt) backoffFor,
  })  : _service = service,
        _cache = cache,
        _wsConnect = wsConnect,
        _backoffFor = backoffFor {
    _blocks = _cache.getBlocks(coupleId);
    // Seed both controllers from cache as soon as a listener attaches.
    _blocksController.onListen = _seedBlocks;
    _overlapController.onListen = _seedOverlap;
    _connect();
  }

  void _seedBlocks() {
    if (!_blocksController.isClosed) _blocksController.add(_blocks);
  }

  void _seedOverlap() {
    if (!_overlapController.isClosed) _overlapController.add(null);
  }

  Future<void> _connect() async {
    if (_disposed) return;
    try {
      final token = await _service.tokenProvider();
      if (token == null) {
        _scheduleReconnect();
        return;
      }
      final uri = Uri.parse('${_service.wsUrl}?token=$token');
      final socket = await _wsConnect(uri);
      if (_disposed) {
        socket.close();
        return;
      }
      _socket = socket;
      _attempt = 0;
      socket.messages.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      // Subscribe to this couple's stream.
      socket.send(jsonEncode({'t': 'sub', 'coupleId': coupleId}));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _socket = null;
    _attempt += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_backoffFor(_attempt), _connect);
  }

  void _onMessage(String raw) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final type = msg['t'] as String?;
      switch (type) {
        case 'block:set':
          _onBlockSet(msg);
          break;
        case 'block:del':
          _onBlockDel(msg);
          break;
        case 'overlap':
          _onOverlap(msg);
          break;
      }
    } catch (_) {
      // Ignore malformed messages; the server is the source of truth and will
      // re-broadcast on the next change.
    }
  }

  void _onBlockSet(Map<String, dynamic> msg) {
    final blockJson = msg['block'] as Map<String, dynamic>?;
    if (blockJson == null) return;
    final id = (blockJson['id'] as String?) ?? (blockJson['blockId'] as String?) ?? '';
    final block = TimeBlock.fromJson(
      Map<String, dynamic>.from(blockJson),
      id,
    );
    final idx = _blocks.indexWhere((b) => b.id == block.id);
    if (idx >= 0) {
      _blocks = [..._blocks]..[idx] = block;
    } else {
      _blocks = [..._blocks, block];
    }
    _cache.putBlock(coupleId, block); // fire-and-forget
    if (!_blocksController.isClosed) _blocksController.add(_blocks);
  }

  void _onBlockDel(Map<String, dynamic> msg) {
    final id = msg['id'] as String?;
    if (id == null) return;
    _blocks = _blocks.where((b) => b.id != id).toList();
    _cache.deleteBlock(coupleId, id); // fire-and-forget
    if (!_blocksController.isClosed) _blocksController.add(_blocks);
  }

  void _onOverlap(Map<String, dynamic> msg) {
    final windowsRaw = msg['windows'] as List<dynamic>?;
    final windows = windowsRaw
            ?.map((e) => OverlapWindow.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        const <OverlapWindow>[];
    final result = OverlapResult(
      windows: windows,
      computedAt: DateTime.now().toUtc(),
      inputHash: (msg['inputHash'] as String?) ?? '',
      computedBy: msg['computedBy'] as String?,
    );
    if (!_overlapController.isClosed) _overlapController.add(result);
  }

  /// Send an `overlap` message upstream (device-computed result). The server
  /// dedups on `inputHash` and pushes FCM to the offline partner.
  Future<void> publishOverlap(OverlapResult result, String computedBy) async {
    final socket = _socket;
    if (socket == null || socket.isClosed) {
      // Ensure a connection is open before sending.
      await _connect();
    }
    final s = _socket;
    if (s == null) {
      throw const SyncException(
        code: 'ws-disconnected',
        message: 'WebSocket is not connected; cannot publish overlap',
      );
    }
    s.send(jsonEncode({
      't': 'overlap',
      'windows': result.windows.map((w) => w.toJson()).toList(),
      'inputHash': result.inputHash,
      'computedBy': computedBy,
    }));
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _socket?.close();
    await _blocksController.close();
    await _overlapController.close();
  }
}

// ---------------------------------------------------------------------------
// SyncService
// ---------------------------------------------------------------------------

/// Drop-in replacement for [FirestoreService] against the self-host VPS
/// backend. HTTP (Bearer = Firebase ID token via [tokenProvider]) for CRUD +
/// pairing; WebSocket for real-time blocks + overlap; Hive cache for offline
/// block rendering on cold start.
///
/// The method surface mirrors [FirestoreService] so V7 can swap the provider
/// wiring without touching call sites.
class SyncService {
  final String baseUrl;
  final String wsUrl;
  final Future<String?> Function() tokenProvider;

  final http.Client _httpClient;
  final WsConnectionFactory _wsConnect;
  final BlockCache _cache;
  final Duration Function(int attempt) _backoffFor;

  final Map<String, _CoupleSession> _sessions = {};
  bool _disposed = false;

  SyncService({
    required this.baseUrl,
    required this.wsUrl,
    required this.tokenProvider,
    http.Client? httpClient,
    WsConnectionFactory? wsConnect,
    BlockCache? cache,
    Duration Function(int attempt)? backoffFor,
  })  : _httpClient = httpClient ?? http.Client(),
        _wsConnect = wsConnect ?? _defaultWsConnect,
        _cache = cache ?? HiveBlockCache(),
        _backoffFor = backoffFor ?? _defaultBackoff;

  static Duration _defaultBackoff(int attempt) {
    // 1s, 2s, 4s, 8s, 16s, then capped at 30s.
    final seconds = (1 << (attempt - 1)).clamp(1, 30);
    return Duration(seconds: seconds);
  }

  // ==========================================================================
  // AUTH / USERS
  // ==========================================================================

  /// GET /users/me — returns the current user (resolved from the Bearer token).
  Future<UserModel?> getUser(String uid) async {
    final res = await _get('/users/me');
    if (res.statusCode == 404) return null;
    final body = _decodeOrThrow(res, 'Failed to get user');
    return UserModel.fromJson(body as Map<String, dynamic>);
  }

  /// POST /auth/verify — exchange the Firebase ID token for a session; upserts
  /// the `users` row. Pass the user fields you want the server to store.
  Future<void> upsertUser(UserModel user) async {
    final res = await _post('/auth/verify', {
      'email': user.email,
      'displayName': user.displayName,
      'photoUrl': user.photoUrl,
      'timezone': user.timezone,
      'showLateNightWindows': user.showLateNightWindows,
    });
    _ensureOk(res, 'Failed to upsert user');
  }

  /// POST /auth/fcm-token — register/refresh the device's FCM token.
  Future<void> registerFcmToken(String token) async {
    final res = await _post('/auth/fcm-token', {'token': token});
    _ensureOk(res, 'Failed to register FCM token');
  }

  // ==========================================================================
  // BLOCKS
  // ==========================================================================

  /// Opens (or reuses) the WS for [coupleId], seeds from the Hive cache, then
  /// emits the live list on every `block:set` / `block:del` message. Mirrors
  /// [FirestoreService.watchBlocks].
  Stream<List<TimeBlock>> watchBlocks(String coupleId, {String? userId}) {
    final session = _ensureSession(coupleId);
    // userId filter is applied client-side for V1 parity; the backend streams
    // all couple blocks and the overlap engine needs both partners' blocks.
    if (userId == null) return session.blocks;
    return session.blocks.map((blocks) =>
        blocks.where((b) => b.userId == userId).toList());
  }

  /// POST /blocks — create a block; returns the server-generated id.
  Future<String> createBlock(String coupleId, TimeBlock block) async {
    final res = await _post('/blocks', {
      'coupleId': coupleId,
      ..._blockToJson(block),
    });
    final body = _decodeOrThrow(res, 'Failed to create block');
    return (body['id'] as String?) ??
        (body['blockId'] as String?) ??
        '';
  }

  /// PUT /blocks/:id — partial update.
  Future<void> updateBlock(
    String coupleId,
    String blockId,
    Map<String, dynamic> data,
  ) async {
    final res = await _put('/blocks/$blockId', data);
    _ensureOk(res, 'Failed to update block');
  }

  /// DELETE /blocks/:id.
  Future<void> deleteBlock(String coupleId, String blockId) async {
    final res = await _delete('/blocks/$blockId');
    _ensureOk(res, 'Failed to delete block');
  }

  /// POST /blocks/batch — atomic replace of google-sourced blocks for a user.
  /// Returns (deletedCount, createdCount) as reported by the server.
  Future<({int deletedCount, int createdCount})>
      atomicReplaceGoogleSourcedBlocks(
    String coupleId,
    String userId,
    List<TimeBlock> blocks,
  ) async {
    final res = await _post('/blocks/batch', {
      'coupleId': coupleId,
      'userId': userId,
      'source': 'google',
      'blocks': blocks.map(_blockToJson).toList(),
    });
    final body = _decodeOrThrow(res,
        'Failed to atomically replace google-sourced blocks') as Map<String, dynamic>;
    return (
      deletedCount: (body['deletedCount'] as num?)?.toInt() ?? 0,
      createdCount: (body['createdCount'] as num?)?.toInt() ?? blocks.length,
    );
  }

  // ==========================================================================
  // OVERLAP
  // ==========================================================================

  /// WS `overlap` messages → emit [OverlapResult]. The device computes locally
  /// and publishes via [publishOverlap]; the server stores + fans out + pushes
  /// FCM to the offline partner. Seeds with `null` (no cached overlap on the
  /// device; the controller recomputes from the block cache).
  Stream<OverlapResult?> watchOverlap(String coupleId) {
    return _ensureSession(coupleId).overlap;
  }

  /// GET /overlaps/latest?coupleId=X — fetch the stored latest overlap (used on
  /// reconnect after being offline).
  Future<OverlapResult?> getOverlap(String coupleId) async {
    final res = await _get('/overlaps/latest?coupleId=$coupleId');
    if (res.statusCode == 404) return null;
    final body = _decodeOrThrow(res, 'Failed to get overlap');
    return OverlapResult.fromJson(body as Map<String, dynamic>);
  }

  /// Send a device-computed [OverlapResult] up the WS as an `overlap` message
  /// with `{windows, inputHash, computedBy}`. The server dedups on inputHash
  /// and pushes FCM to the offline partner. Replaces
  /// [FirestoreService.writeOverlapTransaction].
  Future<void> publishOverlap(String coupleId, OverlapResult result) async {
    final session = _ensureSession(coupleId);
    // computedBy is the calling device's uid; the caller (V7 provider) passes
    // the current user's uid. The session needs a live socket — it opens one on
    // construction, so this is normally a no-op connect.
    await session.publishOverlap(result, result.computedBy ?? '');
  }

  // ==========================================================================
  // PAIRING
  // ==========================================================================

  /// POST /invites — create a 6-char invite code (48h expiry). Returns the code.
  Future<String> createInvite(String createdByUid) async {
    final res = await _post('/invites', {'createdByUid': createdByUid});
    final body = _decodeOrThrow(res, 'Failed to create invite');
    return (body['code'] as String?) ??
        (body['inviteCode'] as String?) ??
        '';
  }

  /// POST /invites/:code/redeem — atomic pairing. Returns the coupleId.
  Future<String> redeemInvite(String code) async {
    final res = await _post('/invites/$code/redeem', {});
    final body = _decodeOrThrow(res, 'Failed to redeem invite');
    return (body['coupleId'] as String?) ??
        (body['couple_id'] as String?) ??
        '';
  }

  /// POST /couples/:id/unpair — port of `unpairCouple`.
  Future<void> unpair(String coupleId) async {
    final res = await _post('/couples/$coupleId/unpair', {});
    _ensureOk(res, 'Failed to unpair');
  }

  // ==========================================================================
  // SESSION + HTTP plumbing
  // ==========================================================================

  _CoupleSession _ensureSession(String coupleId) {
    _checkDisposed();
    return _sessions.putIfAbsent(
      coupleId,
      () => _CoupleSession(
        coupleId: coupleId,
        service: this,
        cache: _cache,
        wsConnect: _wsConnect,
        backoffFor: _backoffFor,
      ),
    );
  }

  Future<http.Response> _get(String path) async {
    final token = await tokenProvider();
    return _httpClient.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
    );
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    final token = await tokenProvider();
    return _httpClient.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> _put(String path, Map<String, dynamic> body) async {
    final token = await tokenProvider();
    return _httpClient.put(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> _delete(String path) async {
    final token = await tokenProvider();
    return _httpClient.delete(
      Uri.parse('$baseUrl$path'),
      headers: _headers(token),
    );
  }

  Map<String, String> _headers(String? token) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  void _ensureOk(http.Response res, String operation) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SyncException(
        code: 'http-${res.statusCode}',
        message: '$operation (HTTP ${res.statusCode})',
        statusCode: res.statusCode,
        originalError: res.body,
      );
    }
  }

  dynamic _decodeOrThrow(http.Response res, String operation) {
    _ensureOk(res, operation);
    if (res.body.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(res.body);
    } catch (e) {
      throw SyncException(
        code: 'decode',
        message: '$operation: invalid JSON response',
        statusCode: res.statusCode,
        originalError: e,
      );
    }
  }

  void _checkDisposed() {
    if (_disposed) {
      throw const SyncException(
        code: 'disposed',
        message: 'SyncService has been disposed',
      );
    }
  }

  /// Close all WS sessions and the HTTP client. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final sessions = _sessions.values.toList();
    _sessions.clear();
    await Future.wait(sessions.map((s) => s.dispose()));
    _httpClient.close();
  }
}
