// lib/presentation/shell/app_shell.dart
//
// SAD v1.1 §4.1.2 — 플랫폼별 네비게이션 레이아웃.
// Windows Desktop: NavigationRail (사이드바)
// Android:         BottomNavigationBar

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _destinations = [
    (path: '/dashboard',    icon: Icons.home_outlined,       label: '대시보드'),
    (path: '/transactions', icon: Icons.receipt_long_outlined,label: '거래내역'),
    (path: '/report',       icon: Icons.bar_chart_outlined,  label: '리포트'),
    (path: '/accounts',     icon: Icons.account_balance_outlined, label: '계좌'),
    (path: '/settings',     icon: Icons.settings_outlined,   label: '설정'),
  ];

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    for (int i = 0; i < _destinations.length; i++) {
      if (loc.startsWith(_destinations[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 720;

    if (isDesktop) {
      return _DesktopShell(child: child);
    }
    return _MobileShell(child: child);
  }
}

// ── Desktop — NavigationRail ───────────────────────────
class _DesktopShell extends StatelessWidget {
  const _DesktopShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    int selected = 0;
    for (int i = 0; i < AppShell._destinations.length; i++) {
      if (loc.startsWith(AppShell._destinations[i].path)) selected = i;
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected,
            labelType: NavigationRailLabelType.all,
            destinations: AppShell._destinations.map((d) =>
              NavigationRailDestination(
                icon:  Icon(d.icon),
                label: Text(d.label),
              ),
            ).toList(),
            onDestinationSelected: (i) =>
                context.go(AppShell._destinations[i].path),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ── Mobile — BottomNavigationBar ──────────────────────
class _MobileShell extends StatelessWidget {
  const _MobileShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    int selected = 0;
    for (int i = 0; i < AppShell._destinations.length; i++) {
      if (loc.startsWith(AppShell._destinations[i].path)) selected = i;
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) =>
            context.go(AppShell._destinations[i].path),
        destinations: AppShell._destinations.map((d) =>
          NavigationDestination(
            icon:  Icon(d.icon),
            label: d.label,
          ),
        ).toList(),
      ),
    );
  }
}
