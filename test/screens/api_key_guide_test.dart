import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_subtitle_translator/screens/api_key_guide_screen.dart';

void main() {
  testWidgets('API 키 발급 안내: 주요 섹션 제목 렌더', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ApiKeyGuideScreen()),
    );

    expect(find.text('API 키 발급 방법'), findsOneWidget); // AppBar 제목
    expect(find.text('1. Google Cloud 프로젝트 만들기'), findsOneWidget);

    // 비용 안내는 목록 하단이라 스크롤해서 확인(ListView는 지연 빌드).
    // SelectableText도 Scrollable이라 바깥 ListView의 Scrollable을 지정한다.
    await tester.scrollUntilVisible(
      find.text('비용 안내'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('비용 안내'), findsOneWidget);
  });
}
