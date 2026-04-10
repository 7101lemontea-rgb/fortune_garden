// lib/app.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_initializer.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/pin_notifier.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/router/app_router.dart';
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

    // PIN 잠금 상태 — go_router 없이 PIN 입력 화면만 표시
    if (!pinState.isLoading && pinState.isLocked) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        home: PinScreen(mode: PinScreenMode.unlock),
      );
    }

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Fortune Garden',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
