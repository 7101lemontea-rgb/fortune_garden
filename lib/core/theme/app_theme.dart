// lib/core/theme/app_theme.dart
//
// Fortune Garden Hybrid 테마
//   Light (D1 Tactile Archivist 기반): 아이보리 크림 배경 + 올리브 그린 primary
//   Dark  (D2 Verdant Atelier 기반):   딥 에메랄드 배경 + 민트 primary
//
// 사용:
//   app.dart의 MaterialApp.router에 아래처럼 적용
//     theme:     AppTheme.light,
//     darkTheme: AppTheme.dark,

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTheme {
  // ── Light (D1) ────────────────────────────────────────────
  static ThemeData get light {
    const primary = Color(0xFF384b2c);
    const primaryContainer = Color(0xFF4f6342);
    const background = Color(0xFFfcf9f0);
    const surface = Color(0xFFffffff);
    const surfaceContainer = Color(0xFFf1eee5);
    const onSurface = Color(0xFF1c1c17);
    const onSurfaceVariant = Color(0xFF44483f);
    const outlineVariant = Color(0xFFc4c8bd);
    const incomeColor = Color(0xFF4edea3);
    const expenseColor = Color(0xFFba1a1a);

    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryContainer,
      onPrimaryContainer: const Color(0xFFc7deb5),
      secondary: const Color(0xFF56642b),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFd6e7a1),
      onSecondaryContainer: const Color(0xFF5a682f),
      tertiary: const Color(0xFF613e17),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFF7c552c),
      onTertiaryContainer: const Color(0xFFffcd9f),
      error: expenseColor,
      onError: Colors.white,
      errorContainer: const Color(0xFFffdad6),
      onErrorContainer: const Color(0xFF93000a),
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: const Color(0xFFe5e2da),
      surfaceContainerHigh: const Color(0xFFebe8df),
      surfaceContainer: surfaceContainer,
      surfaceContainerLow: const Color(0xFFf6f3ea),
      surfaceContainerLowest: Colors.white,
      onSurfaceVariant: onSurfaceVariant,
      outline: const Color(0xFF74786f),
      outlineVariant: outlineVariant,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: const Color(0xFF31312b),
      onInverseSurface: const Color(0xFFf4f1e8),
      inversePrimary: const Color(0xFFb7cea5),
    );

    return _buildTheme(colorScheme);
  }

  // ── Dark (D2) ─────────────────────────────────────────────
  static ThemeData get dark {
    const primary = Color(0xFF4edea3); // 민트
    const primaryContainer = Color(0xFF004f34);
    const background = Color(0xFF0d2a1d); // 딥 에메랄드 그린
    const surface = Color(0xFF1a3d2b);
    const surfaceContainer = Color(0xFF1a3d2b);
    const onSurface = Color(0xFFe0f2e9);
    const onSurfaceVariant = Color(0xFFa8c5b0);
    const outlineVariant = Color(0xFF1d5c3e);
    const expenseColor = Color(0xFFFF6B6B);

    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: const Color(0xFF003622),
      primaryContainer: primaryContainer,
      onPrimaryContainer: const Color(0xFF31c98f),
      secondary: const Color(0xFF505f76),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFd0e1fb),
      onSecondaryContainer: const Color(0xFF54647a),
      tertiary: const Color(0xFF25312b),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFF3b4741),
      onTertiaryContainer: const Color(0xFFa8b5ad),
      error: expenseColor,
      onError: Colors.white,
      errorContainer: const Color(0xFF93000a),
      onErrorContainer: const Color(0xFFffdad6),
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: const Color(0xFF1f4a33),
      surfaceContainerHigh: const Color(0xFF1c4430),
      surfaceContainer: surfaceContainer,
      surfaceContainerLow: const Color(0xFF163626),
      surfaceContainerLowest: background,
      onSurfaceVariant: onSurfaceVariant,
      outline: const Color(0xFF707974),
      outlineVariant: outlineVariant,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: const Color(0xFFe0f2e9),
      onInverseSurface: const Color(0xFF0d2a1d),
      inversePrimary: const Color(0xFF003622),
    );

    return _buildTheme(colorScheme);
  }

  // ── 공통 ThemeData 빌더 ───────────────────────────────────
  static ThemeData _buildTheme(ColorScheme colorScheme) {
    final isLight = colorScheme.brightness == Brightness.light;

    // 세리프 헤드라인 텍스트스타일 (고운 바탕 적용)
    final headlineStyle = GoogleFonts.gowunBatang(
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600, // 굵기 추가 가능
    );

    // 세리프 헤드라인 텍스트스타일
    final headlineStyle2 = GoogleFonts.newsreader(
      fontStyle: FontStyle.italic,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,

      // ── 텍스트 테마 ──────────────────────────────────────
      // headlineSmall/Medium/Large, titleMedium/Large → Newsreader serif
      // 나머지 → 시스템 기본 sans-serif
      textTheme: TextTheme(
        headlineLarge: GoogleFonts.newsreader(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
          color: colorScheme.onSurface,
        ),
        headlineMedium: GoogleFonts.newsreader(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
          color: colorScheme.onSurface,
        ),
        headlineSmall: GoogleFonts.newsreader(
          fontSize: 24,
          fontWeight: FontWeight.w500,
          fontStyle: FontStyle.italic,
          color: colorScheme.onSurface,
        ),
        titleLarge: GoogleFonts.newsreader(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
        titleMedium: GoogleFonts.newsreader(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: colorScheme.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: colorScheme.onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: colorScheme.onSurfaceVariant,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          letterSpacing: 0.5,
          color: colorScheme.onSurfaceVariant,
        ),
      ),

      // ── AppBar ───────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surfaceContainerLowest,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.newsreader(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
          color: colorScheme.primary,
        ),
      ),

      // ── Card ─────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color: isLight ? Colors.white : colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.6),
            width: 1,
          ),
        ),
      ),

      // ── Input ────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),

      // ── Divider ──────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withOpacity(0.4),
        thickness: 1,
      ),

      // ── FAB ──────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFF4edea3), // 민트 고정
        foregroundColor: const Color(0xFF003622),
        elevation: 4,
        shape: const CircleBorder(),
      ),

      // ── SegmentedButton ──────────────────────────────────
      segmentedButtonTheme: const SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
      ),

      // ── NavigationBar (Mobile) ───────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:
            isLight ? const Color(0xFFfcf9f0) : const Color(0xFF0d2a1d),
        indicatorColor: isLight
            ? const Color(0xFF4f6342).withOpacity(0.15)
            : const Color(0xFF4edea3).withOpacity(0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              color:
                  isLight ? const Color(0xFF384b2c) : const Color(0xFF4edea3),
            );
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color:
                  isLight ? const Color(0xFF384b2c) : const Color(0xFF4edea3),
            );
          }
          return TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),

      // ── NavigationRail (Desktop) ─────────────────────────
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor:
            isLight ? const Color(0xFFf6f3ea) : const Color(0xFF0d2a1d),
        selectedIconTheme: IconThemeData(
          color: isLight ? const Color(0xFF384b2c) : const Color(0xFF4edea3),
        ),
        unselectedIconTheme: IconThemeData(
          color: colorScheme.onSurfaceVariant,
        ),
        indicatorColor: isLight
            ? const Color(0xFF4f6342).withOpacity(0.12)
            : const Color(0xFF4edea3).withOpacity(0.12),
      ),
    );
  }

  // ── ThemeMode 변환 ────────────────────────────────────────
  static ThemeMode themeModeFromString(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String stringFromThemeMode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  // ── 의미 색상 (차트·금액 표시용) ─────────────────────────
  static const incomeLight = Color(0xFF4edea3);
  static const incomeDark = Color(0xFF4edea3);
  static const expenseLight = Color(0xFFba1a1a);
  static const expenseDark = Color(0xFFFF6B6B);
}

// ════════════════════════════════════════════════════════════
// GrainOverlay — Scaffold body를 Stack으로 감쌀 때 사용
// ════════════════════════════════════════════════════════════

/// Scaffold의 body를 GrainOverlay로 감싸면 grain 텍스처가 적용됨.
///
/// 사용 예:
/// ```dart
/// Scaffold(
///   body: GrainOverlay(
///     child: YourContentWidget(),
///   ),
/// )
/// ```
class GrainOverlay extends StatelessWidget {
  const GrainOverlay({super.key, required this.child, this.opacity = 0.04});

  final Widget child;

  /// grain 이미지 불투명도 (기본값 0.04, 권장 범위 0.03~0.05)
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Image.asset(
                'assets/images/grain.png',
                repeat: ImageRepeat.repeat,
                fit: BoxFit.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
