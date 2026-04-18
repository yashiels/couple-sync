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
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

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
    _tabController = TabController(length: 2, vsync: this);
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
        children: const [
          ShareCodeTab(),
          EnterCodeTab(),
        ],
      ),
    );
  }
}
