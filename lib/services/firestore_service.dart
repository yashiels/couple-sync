import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/models/models.dart';

/// Exception for Firestore operations with user-friendly messages.
class FirestoreException implements Exception {
  final String code;
  final String message;
  final dynamic originalError;

  const FirestoreException({
    required this.code,
    required this.message,
    this.originalError,
  });

  @override
  String toString() => 'FirestoreException($code): $message';
}

/// Service for all Firestore database operations.
/// Abstracts Firestore complexity and returns typed model objects.
class FirestoreService {
  final FirebaseFirestore _firestore;

  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ============================================================
  // USERS
  // ============================================================

  /// Get a user by UID.
  /// Returns null if the user doesn't exist.
  Future<UserModel?> getUser(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();

      if (!doc.exists) return null;

      return UserModel.fromJson(doc.data()!);
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to get user');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while fetching user',
        originalError: e,
      );
    }
  }

  /// Create a new user document.
  /// Uses server timestamp for createdAt.
  Future<void> createUser(String uid, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to create user');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while creating user',
        originalError: e,
      );
    }
  }

  /// Update an existing user document.
  /// Only updates the fields provided in data.
  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('users').doc(uid).update(data);
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to update user');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while updating user',
        originalError: e,
      );
    }
  }

  // ============================================================
  // COUPLES
  // ============================================================

  /// Get a couple by coupleId.
  /// Returns null if the couple doesn't exist.
  Future<CoupleModel?> getCouple(String coupleId) async {
    try {
      final doc = await _firestore.collection('couples').doc(coupleId).get();

      if (!doc.exists) return null;

      return CoupleModel.fromJson(doc.data()!);
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to get couple');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while fetching couple',
        originalError: e,
      );
    }
  }

  /// Create a new couple document.
  /// Uses server timestamp for createdAt.
  Future<String> createCouple(CoupleModel couple) async {
    try {
      final docRef = await _firestore.collection('couples').add({
        ...couple.toJson(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return docRef.id;
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to create couple');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while creating couple',
        originalError: e,
      );
    }
  }

  // ============================================================
  // INVITES
  // ============================================================

  /// Create a new invite document with the given code.
  /// Uses server timestamp for createdAt (if present in data).
  Future<void> createInvite(String code, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('invites').doc(code).set({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to create invite');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while creating invite',
        originalError: e,
      );
    }
  }

  /// Get an invite by code.
  /// Returns null if the invite doesn't exist.
  Future<InviteModel?> getInvite(String code) async {
    try {
      final doc = await _firestore.collection('invites').doc(code).get();

      if (!doc.exists) return null;

      return InviteModel.fromJson(doc.data()!);
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to get invite');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while fetching invite',
        originalError: e,
      );
    }
  }

  /// Update an existing invite document.
  /// Only updates the fields provided in data.
  Future<void> updateInvite(String code, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('invites').doc(code).update(data);
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to update invite');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while updating invite',
        originalError: e,
      );
    }
  }

  // ============================================================
  // TIME BLOCKS
  // ============================================================

  /// Get all time blocks for a user in a couple.
  /// Returns blocks from the subcollection: timeblocks/{coupleId}/blocks/{blockId}
  Future<List<TimeBlock>> getBlocks(String coupleId, String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .where('userId', isEqualTo: userId)
          .get();

      return querySnapshot.docs
          .map((doc) => TimeBlock.fromJson(doc.data(), doc.id))
          .toList();
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to get blocks');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while fetching blocks',
        originalError: e,
      );
    }
  }

  /// Watches time blocks for a couple, optionally filtered by userId.
  Stream<List<TimeBlock>> watchBlocks(String coupleId, {String? userId}) {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks');

      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }

      return query.snapshots().map((snapshot) {
        return snapshot.docs
            .map((doc) => TimeBlock.fromJson(doc.data(), doc.id))
            .toList();
      }).handleError((error) {
        if (error is FirebaseException) {
          throw _mapFirebaseException(error, 'Failed to watch blocks');
        }
        throw FirestoreException(
          code: 'unknown',
          message: 'An unexpected error occurred while watching blocks',
          originalError: error,
        );
      });
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to watch blocks');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while watching blocks',
        originalError: e,
      );
    }
  }

  /// Create a new time block.
  /// Uses server timestamp for createdAt.
  /// Returns the block ID.
  Future<String> createBlock(String coupleId, TimeBlock block) async {
    try {
      final docRef = await _firestore
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .add({
        ...block.toJson(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      return docRef.id;
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to create block');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while creating block',
        originalError: e,
      );
    }
  }

  /// Update an existing time block.
  /// Only updates the fields provided in data.
  Future<void> updateBlock(
    String coupleId,
    String blockId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _firestore
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .doc(blockId)
          .update(data);
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to update block');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while updating block',
        originalError: e,
      );
    }
  }

  /// Delete a time block.
  Future<void> deleteBlock(String coupleId, String blockId) async {
    try {
      await _firestore
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .doc(blockId)
          .delete();
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to delete block');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while deleting block',
        originalError: e,
      );
    }
  }

  /// Delete all google-sourced blocks for a user.
  /// Used for replace strategy when syncing from Google Calendar.
  Future<int> deleteGoogleSourcedBlocks(String coupleId, String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .where('userId', isEqualTo: userId)
          .where('source', isEqualTo: 'google')
          .get();

      final batch = _firestore.batch();
      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }

      if (querySnapshot.docs.isNotEmpty) {
        await batch.commit();
      }

      return querySnapshot.docs.length;
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to delete google-sourced blocks');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while deleting blocks',
        originalError: e,
      );
    }
  }

  /// Batch create multiple time blocks.
  /// Used for efficiently writing multiple blocks at once.
  Future<int> batchCreateBlocks(String coupleId, List<TimeBlock> blocks) async {
    try {
      if (blocks.isEmpty) return 0;

      final batch = _firestore.batch();
      final collection = _firestore
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks');

      for (final block in blocks) {
        final docRef = collection.doc();
        batch.set(docRef, {
          ...block.toJson(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      return blocks.length;
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to create blocks');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while creating blocks',
        originalError: e,
      );
    }
  }

  /// Atomically replaces all google-sourced blocks for a user with new blocks.
  ///
  /// Fetches existing google-sourced block refs, then stages all deletes and
  /// all new writes into one or more WriteBatches (max 500 ops each) before
  /// committing. No window exists where the old blocks are gone but the new
  /// ones have not yet been written.
  ///
  /// Returns a record of (deletedCount, createdCount).
  Future<({int deletedCount, int createdCount})> atomicReplaceGoogleSourcedBlocks(
    String coupleId,
    String userId,
    List<TimeBlock> newBlocks,
  ) async {
    try {
      final collection = _firestore
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks');

      // Fetch existing google-sourced block references.
      final querySnapshot = await collection
          .where('userId', isEqualTo: userId)
          .where('source', isEqualTo: 'google')
          .get();

      final deleteRefs = querySnapshot.docs.map((d) => d.reference).toList();

      // Build list of all operations: deletes first, then sets.
      // Each entry is a function that stages an op onto a WriteBatch.
      // Firestore batches support up to 500 operations.
      const int batchLimit = 500;

      // Collect all staged operations as closures over a WriteBatch.
      final List<void Function(WriteBatch)> operations = [
        for (final ref in deleteRefs) (WriteBatch b) => b.delete(ref),
        for (final block in newBlocks)
          (WriteBatch b) => b.set(
                collection.doc(),
                {
                  ...block.toJson(),
                  'createdAt': FieldValue.serverTimestamp(),
                },
              ),
      ];

      // Chunk into batches of batchLimit and commit sequentially.
      for (int i = 0; i < operations.length; i += batchLimit) {
        final chunk = operations.sublist(
          i,
          (i + batchLimit).clamp(0, operations.length),
        );
        final batch = _firestore.batch();
        for (final op in chunk) {
          op(batch);
        }
        await batch.commit();
      }

      return (
        deletedCount: deleteRefs.length,
        createdCount: newBlocks.length,
      );
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(
        e,
        'Failed to atomically replace google-sourced blocks',
      );
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message:
            'An unexpected error occurred while replacing google-sourced blocks',
        originalError: e,
      );
    }
  }

  // ============================================================
  // OVERLAP
  // ============================================================

  /// Get the overlap result for a couple.
  /// Reads from: overlaps/{coupleId}/windows/latest
  Future<OverlapResult?> getOverlap(String coupleId) async {
    try {
      final doc = await _firestore
          .collection('overlaps')
          .doc(coupleId)
          .collection('windows')
          .doc('latest')
          .get();

      if (!doc.exists) return null;

      return OverlapResult.fromJson(doc.data()!);
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to get overlap');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while fetching overlap',
        originalError: e,
      );
    }
  }

  /// Watches the latest overlap result for a couple.
  Stream<OverlapResult?> watchOverlap(String coupleId) {
    try {
      return _firestore
          .collection('overlaps')
          .doc(coupleId)
          .collection('windows')
          .doc('latest')
          .snapshots()
          .map((snapshot) {
        if (!snapshot.exists) return null;
        return OverlapResult.fromJson(snapshot.data()!);
      }).handleError((error) {
        if (error is FirebaseException) {
          throw _mapFirebaseException(error, 'Failed to watch overlap');
        }
        throw FirestoreException(
          code: 'unknown',
          message: 'An unexpected error occurred while watching overlap',
          originalError: error,
        );
      });
    } on FirebaseException catch (e) {
      throw _mapFirebaseException(e, 'Failed to watch overlap');
    } catch (e) {
      throw FirestoreException(
        code: 'unknown',
        message: 'An unexpected error occurred while watching overlap',
        originalError: e,
      );
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  /// Maps FirebaseException to FirestoreException with user-friendly messages.
  FirestoreException _mapFirebaseException(
    FirebaseException e,
    String operation,
  ) {
    String message;
    String code = e.code;

    switch (e.code) {
      case 'permission-denied':
        message = 'You do not have permission to perform this operation';
        break;
      case 'not-found':
        message = 'The requested document was not found';
        break;
      case 'already-exists':
        message = 'The document already exists';
        break;
      case 'unavailable':
        message = 'Service temporarily unavailable. Please try again later';
        break;
      case 'deadline-exceeded':
        message = 'Operation timed out. Please try again';
        break;
      case 'resource-exhausted':
        message = 'Too many requests. Please try again later';
        break;
      case 'cancelled':
        message = 'Operation was cancelled';
        break;
      case 'unauthenticated':
        message = 'Authentication required. Please sign in again';
        break;
      default:
        message = '$operation. Please try again';
    }

    return FirestoreException(
      code: code,
      message: message,
      originalError: e,
    );
  }
}
