import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

class VideoSubtitleTranslatorApp extends StatelessWidget {
  const VideoSubtitleTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '인프레임',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // 앱 전역 하단/좌우 인셋 처리(Android 15 edge-to-edge에서 내용이 내비게이션
      // 버튼과 겹치지 않도록). 상단은 각 화면의 AppBar가 처리하므로 top:false.
      builder: (context, child) => SafeArea(
        top: false,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeScreen(),
    );
  }
}
