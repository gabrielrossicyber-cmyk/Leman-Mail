import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../dashboard/security_dashboard_screen.dart';
import '../health/health_score_screen.dart';
import '../inbox/unified_inbox_screen.dart';
import '../newsletter/newsletter_cleaner_screen.dart';
import '../security_center/security_center_screen.dart';

/// Bottom-navigation shell: Inbox · Nettoyage · Dashboard · Santé · Sécurité.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          UnifiedInboxScreen(),
          NewsletterCleanerScreen(),
          SecurityDashboardScreen(),
          HealthScoreScreen(),
          SecurityCenterScreen(),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              onPressed: () => context.push('/compose'),
              child: const Icon(Icons.edit_outlined),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox),
            label: 'Boîte',
          ),
          NavigationDestination(
            icon: Icon(Icons.cleaning_services_outlined),
            selectedIcon: Icon(Icons.cleaning_services),
            label: 'Nettoyage',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Santé',
          ),
          NavigationDestination(
            icon: Icon(Icons.security_outlined),
            selectedIcon: Icon(Icons.security),
            label: 'Sécurité',
          ),
        ],
      ),
    );
  }
}
