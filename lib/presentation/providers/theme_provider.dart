// lib/presentation/providers/theme_provider.dart
//
// DB의 'theme' 설정값을 실시간으로 구독해 ThemeMode를 제공.
// app.dart의 MaterialApp.router(themeMode:)에 바인딩됨.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';

/// 'theme' 설정값 → ThemeMode 변환 헬퍼
ThemeMode _toThemeMode(String? value) => switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system, // 'system' 또는 null
    };

/// DB의 app_settings.theme 값을 실시간 구독하는 Provider.
///
/// - SettingsScreen에서 set('theme', 'dark') 호출
/// - → DB 변경 → watchValue() Stream emit
/// - → themeProvider 재계산 → app.dart MaterialApp 재빌드
/// - → 앱 전체 테마 즉시 전환
final themeProvider = StreamProvider<ThemeMode>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return repo.watchValue('theme', defaultValue: 'system').map(_toThemeMode);
});
