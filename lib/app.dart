// lib/app.dart
//
// 앱 루트 위젯. go_router 연결 및 initializeApp() 호출.
//
// 변경 이력:
//   - themeProvider 구독 추가 → SettingsScreen 테마 선택이 앱에 실시간 반영

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_initializer.dart';
import 'presentation/router/app_router.dart';
import 'presentation/providers/theme_provider.dart';

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
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

    // DB의 'theme' 값을 실시간 구독. 변경 즉시 MaterialApp이 재빌드됨.
    // loading / error 시에는 system 테마로 폴백.
    final themeMode = ref.watch(themeProvider).valueOrNull ?? ThemeMode.system;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Fortune Garden',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
        brightness: Brightness.dark,
      ),
      themeMode: themeMode, // ← 핵심: DB 값에 따라 light / dark / system
      routerConfig: router,
    );
  }
}
