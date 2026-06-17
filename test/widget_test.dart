import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_subtitle_translator/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen 렌더링: 파일 선택/URL 진입 요소 표시', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: HomeScreen()),
      ),
    );

    expect(find.text('영상 파일 선택'), findsOneWidget);
    expect(find.text('URL 재생'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
