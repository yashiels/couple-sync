import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../widgets/share_code_tab.dart';
import '../widgets/enter_code_tab.dart';

/// Pairing screen with two tabs for sharing and entering invite codes.
/// Listens for coupleId changes so the screen navigates away when
/// the partner redeems the invite (even if this device shared the code).
///
/// Pass [initialCode] when navigating here from a deep-linked invite URL so
/// the screen switches directly to the "Enter Code" tab and pre-fills the
/// invite code field. The router reads the `code` query parameter and passes
/// it via the GoRoute builder.
class PairingScreen extends ConsumerStatefulWidget {
  /// Invite code to pre-fill in the Enter Code tab (may be null).
  final String? initialCode;

  const PairingScreen({super.key, this.initialCode});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription<DocumentSnapshot>? _userDocSub;

  @override
  void initState() {
    super.initState();
    // Start on "Enter Code" tab (index 1) when arriving via a deep link.
    final startIndex = (widget.initialCode?.isNotEmpty == true) ? 1 : 0;
    _tabController = TabController(length: 2, vsync: this, initialIndex: startIndex);
    _listenForPairing();
  }

  /// Listen to the current user's Firestore doc for coupleId changes.
  /// When the partner redeems the invite, coupleId is set by the Cloud Function.
  void _listenForPairing() {
    final uid = ref.read(authStateProvider).uid;
    if (uid == null) return;

    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data();
      if (data != null && data['coupleId'] != null) {
        // Partner paired — refresh auth state so router redirects to home
        ref.read(authStateProvider.notifier).refreshProfile();
      }
    });
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair with Partner'),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Share Code'),
            Tab(text: 'Enter Code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const ShareCodeTab(),
          EnterCodeTab(initialCode: widget.initialCode),
        ],
      ),
    );
  }
}
