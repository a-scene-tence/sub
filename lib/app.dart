import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

class VideoSubtitleTranslatorApp extends StatelessWidget {
  const VideoSubtitleTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '영상 번역 자막',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B6EF6)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
