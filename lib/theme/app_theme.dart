import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 라이트 "페이퍼" 팔레트 — 화이트·아이보리 모노크롬(포인트 색 없음).
///
/// 색으로 강조하지 않고 여백·타이포·hairline으로 위계를 만든다. 활성 컨트롤도 잉크(검정)로만.
class AppPalette {
  AppPalette._();

  static const Color paper = Color(0xFFFAF9F5); // near-white 아이보리 배경
  static const Color ink = Color(0xFF1A1A1A); // 본문·헤드라인(부드러운 검정)
  static const Color inkSoft = Color(0xFF8C8A85); // 캡션·보조 텍스트(중성 그레이)
  static const Color hairline = Color(0x141A1A1A); // ink ~8%(구분선·밑줄)
  static const Color line = Color(0x331A1A1A); // ink ~20%(보더)
}

/// 앱 전역 테마. 전부 Noto Sans KR(올-산세리프), 굵은 무게 없이 라이트/레귤러/미디엄만 사용.
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
      secondary: AppPalette.ink,
    );

    // 라틴은 Inter, 한글 글리프는 Inter와 어울리는 IBM Plex Sans KR로 폴백.
    final krFallback = <String>[GoogleFonts.ibmPlexSansKr().fontFamily!];
    final inter = GoogleFonts.interTextTheme(base.textTheme);
    final textTheme = inter
        .copyWith(
          displayLarge: inter.displayLarge
              ?.copyWith(fontWeight: FontWeight.w300, letterSpacing: -1.0, height: 1.05),
          displayMedium: inter.displayMedium
              ?.copyWith(fontWeight: FontWeight.w300, letterSpacing: -0.8, height: 1.05),
          displaySmall: inter.displaySmall
              ?.copyWith(fontWeight: FontWeight.w300, letterSpacing: -0.5),
          headlineMedium: inter.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w400, letterSpacing: -0.3),
          headlineSmall: inter.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w400, letterSpacing: -0.2),
          titleLarge: inter.titleLarge?.copyWith(fontWeight: FontWeight.w500),
          bodyLarge: inter.bodyLarge?.copyWith(fontWeight: FontWeight.w400, height: 1.55),
          bodyMedium: inter.bodyMedium?.copyWith(fontWeight: FontWeight.w400, height: 1.55),
          bodySmall: inter.bodySmall?.copyWith(color: AppPalette.inkSoft, height: 1.5),
          labelLarge: inter.labelLarge
              ?.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.2),
        )
        .apply(
          bodyColor: AppPalette.ink,
          displayColor: AppPalette.ink,
          fontFamilyFallback: krFallback,
        );

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
        titleTextStyle: GoogleFonts.inter(
          color: AppPalette.ink,
          fontWeight: FontWeight.w500,
          fontSize: 18,
        ).copyWith(fontFamilyFallback: krFallback),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppPalette.ink,
          foregroundColor: AppPalette.paper,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 15,
            letterSpacing: 0.2,
          ).copyWith(fontFamilyFallback: krFallback),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppPalette.ink,
          side: const BorderSide(color: AppPalette.line, width: 1),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500)
              .copyWith(fontFamilyFallback: krFallback),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppPalette.ink),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: UnderlineInputBorder(),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppPalette.ink, width: 1.5),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppPalette.line, width: 1),
        ),
        labelStyle: TextStyle(color: AppPalette.inkSoft),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppPalette.ink : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppPalette.ink.withValues(alpha: 0.45)
                : null),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppPalette.ink,
        thumbColor: AppPalette.ink,
        inactiveTrackColor: AppPalette.hairline,
      ),
    );
  }
}
