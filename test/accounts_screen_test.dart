// test/accounts_screen_test.dart
//
// 계좌 관리 화면(SCR-007) 회귀 테스트.
//
// 릴리스 빌드에서 발견된 문제를 재현·검증한다.
//   계좌 삭제 후 화면이 검게 변함
//   원인: 삭제 확인 다이얼로그가 바깥 context로 pop해서,
//         ShellRoute의 Navigator가 현재 페이지를 닫아버림
//         ("You have popped the last page off of the stack").
//
// 실제 AccountsScreen을 ShellRoute 안에 올리고 인메모리 DB로 실행한다.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fortune_garden/data/database/app_database.dart';
import 'package:fortune_garden/data/database/database_provider.dart';
import 'package:fortune_garden/presentation/screens/accounts/accounts_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    // 테스트 환경에서는 폰트를 네트워크로 받을 수 없다.
    GoogleFonts.config.allowRuntimeFetching = false;

    db = AppDatabase(NativeDatabase.memory());

    final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    await db.into(db.profiles).insert(ProfilesCompanion.insert(
        name: '첫째프로필', colorHex: '#2E6DA4', createdAt: now));
    await db.into(db.profiles).insert(ProfilesCompanion.insert(
        name: '둘째프로필', colorHex: '#A64A8C', createdAt: now));

    await db.into(db.institutions).insert(InstitutionsCompanion.insert(
        code: 'WOORI', name: '우리은행', type: 'bank'));

    // 첫째 프로필에 계좌 1개
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          profileId: 1,
          institutionCode: 'WOORI',
          accountNumberEnc: Uint8List.fromList([1, 2, 3]),
          alias: const Value('삭제대상통장'),
        ));
  });

  tearDown(() => db.close());

  /// AccountsScreen을 앱과 같은 ShellRoute 구조로 띄운다.
  Future<void> pumpScreen(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/accounts',
      routes: [
        ShellRoute(
          builder: (_, __, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/accounts',
              builder: (_, __) => const AccountsScreen(),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('계좌 삭제 후에도 화면이 유지되고 계좌만 사라진다', (tester) async {
    await pumpScreen(tester);
    expect(find.text('삭제대상통장'), findsOneWidget);

    // 계좌 탭 → 옵션 시트 → 계좌 삭제 → 확인
    await tester.tap(find.text('삭제대상통장'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계좌 삭제'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    // 화면이 살아 있고(검은 화면 아님), 예외 없이, 계좌만 삭제됐다
    expect(tester.takeException(), isNull);
    expect(find.byType(AccountsScreen), findsOneWidget);
    expect(find.text('계좌 관리'), findsOneWidget);
    expect(find.text('삭제대상통장'), findsNothing);
    expect(await db.select(db.accounts).get(), isEmpty);
  });

  testWidgets('삭제 확인에서 취소해도 화면이 유지되고 계좌가 남는다', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('삭제대상통장'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계좌 삭제'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AccountsScreen), findsOneWidget);
    expect(find.text('삭제대상통장'), findsOneWidget);
    expect(await db.select(db.accounts).get(), hasLength(1));
  });

}
