import 'package:flutter/material.dart';

/// Gemini(Google AI Studio) API 키 발급 방법과 비용을 안내하는 정적 페이지.
///
/// 외부 링크는 탭하지 않고 복사용 [SelectableText]로만 표기한다(추가 플러그인 없음).
class ApiKeyGuideScreen extends StatelessWidget {
  const ApiKeyGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API 키 발급 방법')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const <Widget>[
          Text(
            '이 앱은 음성 인식과 번역을 모두 Gemini로 처리합니다. Google AI Studio에서 '
            'Gemini API 키 하나만 발급해 입력하면 됩니다. (Google Cloud 프로젝트·결제 설정은 '
            '필요 없습니다.)',
          ),
          SizedBox(height: 20),
          _Section(
            title: '1. Google AI Studio 접속',
            body: 'Google 계정으로 아래 주소에 접속합니다.',
            url: 'https://aistudio.google.com/apikey',
          ),
          _Section(
            title: '2. API 키 만들기',
            body: '“Create API key(API 키 만들기)”를 눌러 키를 생성합니다. 기존 프로젝트가 '
                '없으면 자동으로 만들어 줍니다.',
          ),
          _Section(
            title: '3. 앱에 키 입력하기',
            body: '복사한 키를 이 앱의 “설정 > Gemini API 키” 입력란에 붙여넣고 '
                '“Gemini 키 저장”을 누르면 됩니다.',
          ),
          _Section(
            title: '비용 안내',
            body: 'Gemini는 오디오·텍스트 토큰 단위로 과금됩니다. 이 앱의 실시간 자막은 '
                '“보고 있는 15초 구간”만 호출하고, 한 번의 호출로 전사와 번역을 함께 처리하므로 '
                '비용이 매우 적습니다. AI Studio에는 무료 사용 한도(분당/일당 요청 수 제한)가 '
                '있어 가벼운 사용은 무료로 충분할 수 있습니다.\n\n'
                '무료 한도와 단가는 계정·시점에 따라 달라질 수 있으니 아래 공식 페이지에서 '
                '확인하세요.',
            url: 'https://ai.google.dev/gemini-api/docs/pricing',
          ),
        ],
      ),
    );
  }
}

/// 안내 섹션: 굵은 제목 + 본문 + 선택적 복사용 URL.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body, this.url});

  final String title;
  final String body;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(body),
          if (url != null) ...<Widget>[
            const SizedBox(height: 6),
            SelectableText(
              url!,
              style: const TextStyle(color: Colors.blue),
            ),
          ],
        ],
      ),
    );
  }
}
