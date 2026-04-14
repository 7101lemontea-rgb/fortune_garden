// lib/presentation/router/app_router.dart
//
// SAD v1.1 §4.1.2 — go_router 기반 라우팅.
// 앱 시작 시 프로필 존재 여부에 따라 /setup 또는 /dashboard로 분기.
//
// ※ 주의: 하위 라우트에서 정적 경로('new')는 동적 경로(':id')보다
//         반드시 먼저 선언해야 합니다. 순서가 바뀌면 go_router가
//         'new'를 id로 파싱하여 FormatException이 발생합니다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_providers.dart';
import '../screens/setup/setup_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/transactions/transactions_screen.dart';
import '../screens/transactions/transaction_detail_screen.dart';
import '../screens/transactions/transaction_new_screen.dart';
import '../screens/report/report_screen.dart';
import '../screens/accounts/accounts_screen.dart';
import '../screens/import/import_screen.dart';
import '../screens/categories/categories_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/profiles/profiles_screen.dart';
import '../shell/app_shell.dart';

// ── Provider ──────────────────────────────────────────
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) async {
      // SAD v1.1 §5.1 — 프로필 0개 → /setup, 1개 이상 → /dashboard
      final activeProfile = await ref.read(activeProfileProvider.future);
      final isSetup = state.matchedLocation == '/setup';

      if (activeProfile == null && !isSetup) return '/setup';
      if (activeProfile != null && isSetup) return '/dashboard';
      return null;
    },
    routes: [
      // SCR-001 — 초기 설정 (쉘 없이 단독 표시)
      GoRoute(
        path: '/setup',
        builder: (_, __) => const SetupScreen(),
      ),

      // 메인 쉘 — NavigationRail (Desktop) / BottomNavigationBar (Mobile)
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          // SCR-002 — 대시보드
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const DashboardScreen(),
          ),

          // SCR-003 — 거래 내역
          GoRoute(
            path: '/transactions',
            builder: (_, __) => const TransactionsScreen(),
            routes: [
              // SCR-005 — 수동 거래 입력
              // ※ 정적 경로 'new'를 동적 경로 ':id' 보다 먼저 선언
              GoRoute(
                path: 'new',
                builder: (_, __) => const TransactionNewScreen(),
              ),
              // SCR-004 — 거래 상세/수정
              GoRoute(
                path: ':id',
                builder: (_, state) => TransactionDetailScreen(
                  id: int.parse(state.pathParameters['id']!),
                ),
              ),
            ],
          ),

          // SCR-006 — 리포트
          GoRoute(
            path: '/report',
            builder: (_, __) => const ReportScreen(),
          ),

          // SCR-007 — 계좌 관리
          GoRoute(
            path: '/accounts',
            builder: (_, __) => const AccountsScreen(),
          ),

          // SCR-008 — CSV 가져오기
          GoRoute(
            path: '/import',
            builder: (_, __) => const ImportScreen(),
          ),

          // SCR-009 — 카테고리 설정
          GoRoute(
            path: '/categories',
            builder: (_, __) => const CategoriesScreen(),
          ),

          // SCR-010 — 앱 설정
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),

          // SCR-011 — 프로필 관리
          GoRoute(
            path: '/profiles',
            builder: (_, __) => const ProfilesScreen(),
          ),
        ],
      ),
    ],
  );
});
