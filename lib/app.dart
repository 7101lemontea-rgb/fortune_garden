// lib/app.dart
//
// 앱 루트 위젯.
//
// 변경 이력:
//   - themeProvider 구독 추가 → 테마 실시간 반영
//   - pinLockProvider 구독 추가 → PIN 잠금 오버레이 적용
//   - AppLifecycleListener 추가 → 백그라운드/포그라운드 자동 잠금

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_initializer.dart';
import 'presentation/router/app_router.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/pin_notifier.dart';
import 'presentation/screens/pin/pin_screen.dart';

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _initialized = false;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _init();

    // 앱 생명주기 감지 — 백그라운드/포그라운드 자동 잠금
    _lifecycleListener = AppLifecycleListener(
      onHide: () => ref.read(pinLockProvider.notifier).onBackground(),
      onInactive: () => ref.read(pinLockProvider.notifier).onBackground(),
      onResume: () => ref.read(pinLockProvider.notifier).onForeground(),
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await initializeApp(ref);
    if (mounted) setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeProvider).valueOrNull ?? ThemeMode.system;
    final pinState = ref.watch(pinLockProvider);

    // 공통 ThemeData
    final lightTheme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.green,
      brightness: Brightness.light,
    );
    final darkTheme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.green,
      brightness: Brightness.dark,
    );

    // PIN 잠금 상태 — router 없이 PIN 입력 화면만 표시
    if (!pinState.isLoading && pinState.isLocked) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        home: PinScreen(mode: PinScreenMode.unlock),
      );
    }

    // 정상 상태 — go_router 적용
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Fortune Garden',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
