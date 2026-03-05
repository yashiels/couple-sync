import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/couple_model.dart';

/// Manages partner pairing via short invite codes and the resulting couple
/// relationship in Firestore.
class PairingService {
  final FirebaseFirestore _db;
  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _codeLength = 6;
  static const _codeValidHours = 48;

  PairingService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  // --- Invite Code Generation ---

  /// Generates a fresh 6-char invite code and writes it to Firestore.
  ///
  /// Throws if the user is already in a couple.
  Future<String> generateInviteCode(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    if (userDoc.exists) {
      final data = userDoc.data();
      if (data != null && data['coupleId'] != null) {
        throw Exception('Already in a couple');
      }
    }

    final rng = Random.secure();
    final code = List.generate(
      _codeLength,
      (_) => _codeChars[rng.nextInt(_codeChars.length)],
    ).join();

    final invite = InviteModel(
      code: code,
      createdByUid: uid,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: _codeValidHours)),
      status: InviteStatus.pending,
    );

    await _db.collection('invites').doc(code).set(invite.toFirestore());
    return code;
  }

  /// Fetches the current user's active invite, if any.
  Future<InviteModel?> getActiveInviteForUser(String uid) async {
    final snap = await _db
        .collection('invites')
        .where('createdByUid', isEqualTo: uid)
        .where('status', isEqualTo: InviteStatus.pending.name)
        .orderBy('expiresAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final invite = InviteModel.fromFirestore(snap.docs.first);
    if (invite.expiresAt.isBefore(DateTime.now().toUtc())) return null;
    return invite;
  }

  // --- Pairing ---

  /// Redeems an invite code and creates the couple relationship.
  ///
  /// Throws if the redeemer is already in a couple.
  Future<CoupleModel> redeemInviteCode({
    required String code,
    required String redeemerUid,
  }) async {
    // Guard: redeemer must not already be in a couple.
    final redeemerDoc = await _db.collection('users').doc(redeemerUid).get();
    if (redeemerDoc.exists) {
      final data = redeemerDoc.data();
      if (data != null && data['coupleId'] != null) {
        throw Exception('Already in a couple');
      }
    }

    final inviteRef = _db.collection('invites').doc(code.toUpperCase());
    final inviteSnap = await inviteRef.get();

    if (!inviteSnap.exists) throw Exception('Invite code not found.');

    final invite = InviteModel.fromFirestore(inviteSnap);

    if (invite.status != InviteStatus.pending) {
      throw Exception('This code has already been used.');
    }
    if (invite.expiresAt.isBefore(DateTime.now().toUtc())) {
      throw Exception('This code has expired.');
    }
    if (invite.createdByUid == redeemerUid) {
      throw Exception('You cannot use your own invite code.');
    }

    final coupleId = const Uuid().v4();
    final couple = CoupleModel(
      coupleId: coupleId,
      userAUid: invite.createdByUid,
      userBUid: redeemerUid,
      pairedAt: DateTime.now().toUtc(),
    );

    final batch = _db.batch();
    // Create couple document
    batch.set(_db.collection('couples').doc(coupleId), couple.toFirestore());
    // Update both user documents with coupleId
    batch.update(_db.collection('users').doc(invite.createdByUid), {'coupleId': coupleId});
    batch.update(_db.collection('users').doc(redeemerUid), {'coupleId': coupleId});
    // Mark invite as accepted
    batch.update(inviteRef, {'status': InviteStatus.accepted.name});

    await batch.commit();
    return couple;
  }

  // --- Fetching ---

  /// Fetches the [CoupleModel] for the given [coupleId], or `null` if not found.
  Future<CoupleModel?> getCoupleById(String coupleId) async {
    final doc = await _db.collection('couples').doc(coupleId).get();
    if (!doc.exists) return null;
    return CoupleModel.fromFirestore(doc);
  }

  /// Streams real-time updates for the couple document with [coupleId].
  Stream<CoupleModel?> watchCouple(String coupleId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .snapshots()
        .map((snap) => snap.exists ? CoupleModel.fromFirestore(snap) : null);
  }

  // --- Unpairing ---

  /// Removes the couple relationship and clears `coupleId` from both user docs.
  Future<void> unpair(CoupleModel couple) async {
    final batch = _db.batch();
    batch.delete(_db.collection('couples').doc(couple.coupleId));
    batch.update(
      _db.collection('users').doc(couple.userAUid),
      {'coupleId': FieldValue.delete()},
    );
    batch.update(
      _db.collection('users').doc(couple.userBUid),
      {'coupleId': FieldValue.delete()},
    );
    await batch.commit();
  }
}
