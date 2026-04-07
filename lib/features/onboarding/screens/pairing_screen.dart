import 'package:flutter/material.dart';
import '../widgets/share_code_tab.dart';
import '../widgets/enter_code_tab.dart';

/// Pairing screen with two tabs for sharing and entering invite codes.
/// Tab 1 (Share): Generate code, copy, and share
/// Tab 2 (Enter): Enter partner's code and redeem
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
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
