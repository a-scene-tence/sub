import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 에디토리얼(잡지/출판물) 톤의 라이트 "페이퍼" 팔레트.
///
/// 모노크롬(잉크/페이퍼) 위에 절제된 포인트 1색(브릭)을 활성 상태에만 소량 쓴다.
class AppPalette {
  AppPalette._();

  static const Color paper = Color(0xFFF4F1EA); // 웜 아이보리 배경
  static const Color ink = Color(0xFF1C1B18); // 거의 검정(본문·헤드라인)
  static const Color inkSoft = Color(0xFF726C5F); // 캡션·보조 텍스트
  static const Color accent = Color(0xFF9C3B1B); // 브릭(포인트, 소량)
  static const Color hairline = Color(0x241C1B18); // ink ~14%(구분선·밑줄)
}

/// 앱 전역 에디토리얼 테마. 헤드라인/타이틀은 Noto Serif KR, 본문은 Noto Sans KR.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppPalette.ink,
      brightness: Brightness.light,
    ).copyWith(
      surface: AppPalette.paper,
      onSurface: AppPalette.ink,
      primary: AppPalette.ink,
      onPrimary: AppPalette.paper,
      secondary: AppPalette.accent,
    );

    final serif = GoogleFonts.notoSerifKrTextTheme(base.textTheme);
    final sans = GoogleFonts.notoSansKrTextTheme(base.textTheme);
    final textTheme = sans.copyWith(
      displayLarge: serif.displayLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      displayMedium: serif.displayMedium
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      displaySmall: serif.displaySmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      headlineMedium:
          serif.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall:
          serif.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: serif.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: sans.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: sans.bodyMedium?.copyWith(height: 1.5),
      bodySmall: sans.bodySmall?.copyWith(color: AppPalette.inkSoft, height: 1.45),
      labelLarge:
          sans.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.4),
    ).apply(bodyColor: AppPalette.ink, displayColor: AppPalette.ink);

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppPalette.paper,
      canvasColor: AppPalette.paper,
      textTheme: textTheme,
      dividerTheme: const DividerThemeData(
        color: AppPalette.hairline,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppPalette.paper,
        foregroundColor: AppPalette.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.notoSerifKr(
          color: AppPalette.ink,
          fontWeight: FontWeight.w700,
          fontSize: 22,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppPalette.ink,
          foregroundColor: AppPalette.paper,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppPalette.ink,
          side: const BorderSide(color: AppPalette.ink, width: 1),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppPalette.accent),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: UnderlineInputBorder(),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppPalette.ink, width: 1.5),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppPalette.hairline, width: 1),
        ),
        labelStyle: TextStyle(color: AppPalette.inkSoft),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppPalette.accent : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppPalette.accent.withValues(alpha: 0.35)
                : null),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppPalette.accent,
        thumbColor: AppPalette.accent,
        inactiveTrackColor: AppPalette.hairline,
      ),
    );
  }
}
