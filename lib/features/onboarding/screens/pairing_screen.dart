import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../../../services/providers/sync_provider.dart';
import '../widgets/share_code_tab.dart';
import '../widgets/enter_code_tab.dart';

/// Pairing screen with two tabs for sharing and entering invite codes.
/// Polls the backend for the current user's coupleId so the screen navigates
/// away when the partner redeems the invite (even if this device shared the
/// code).
///
/// Pass [initialCode] when navigating here from a deep-linked invite URL so
/// the screen switches directly to the "Enter Code" tab and pre-fills the
/// invite code field.
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
  Timer? _pairPoll;

  @override
  void initState() {
    super.initState();
    // Start on "Enter Code" tab (index 1) when arriving via a deep link.
    final startIndex = (widget.initialCode?.isNotEmpty == true) ? 1 : 0;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: startIndex,
    );
    _pollForPairing();
  }

  /// Poll the backend (GET /users/me) every 3s for coupleId. When the partner
  /// redeems the invite the backend sets coupleId on this user; we refresh the
  /// auth state so the router redirects to home.
  // TODO(v8): replace polling with a push channel (WS user-namespace or FCM
  // data message) once the backend supports it.
  void _pollForPairing() {
    final uid = ref.read(authStateProvider).uid;
    if (uid == null) return;
    final sync = ref.read(syncServiceProvider);
    _pairPoll = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final user = await sync.getUser(uid);
        if (user?.coupleId != null) {
          _pairPoll?.cancel();
          if (mounted) {
            ref.read(authStateProvider.notifier).refreshProfile();
          }
        }
      } catch (_) {
        // Network blip — keep polling.
      }
    });
  }

  @override
  void dispose() {
    _pairPoll?.cancel();
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
