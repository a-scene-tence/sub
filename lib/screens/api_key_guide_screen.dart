import 'package:flutter/material.dart';

/// Google Cloud 개인 API 키 발급 방법과 비용을 안내하는 정적 페이지.
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
            '이 앱은 음성 인식·번역에 Google Cloud API를 사용합니다. 아래 절차로 '
            '본인 API 키를 발급해 입력하세요.',
          ),
          SizedBox(height: 20),
          _Section(
            title: '1. Google Cloud 프로젝트 만들기',
            body: 'Google Cloud Console에 접속해 새 프로젝트를 만듭니다. API를 사용하려면 '
                '프로젝트에 결제(청구) 계정을 연결해야 합니다.',
            url: 'https://console.cloud.google.com/',
          ),
          _Section(
            title: '2. 필요한 API 사용 설정',
            body: '“API 및 서비스 > 라이브러리”에서 아래 두 가지를 검색해 “사용 설정”합니다.\n'
                '• Cloud Speech-to-Text API (음성 인식)\n'
                '• Cloud Translation API (번역)\n\n'
                '자연스러운 구어체 번역(Gemini)은 아래 6번에서 별도 키로 설정합니다.',
          ),
          _Section(
            title: '3. API 키 만들기',
            body: '“API 및 서비스 > 사용자 인증 정보(Credentials)”로 이동해 '
                '“사용자 인증 정보 만들기 > API 키”를 선택하면 키가 생성됩니다.',
          ),
          _Section(
            title: '4. 키 제한하기 (필수)',
            body: '생성된 키를 눌러 “API 제한”에서 Speech-to-Text, Translation API로만 '
                '사용을 제한하세요. 2026년 6월부터 제한이 전혀 없는 키는 거부될 수 있으므로 '
                '반드시 제한을 설정해야 합니다.',
          ),
          _Section(
            title: '5. 앱에 키 입력하기',
            body: '복사한 API 키를 이 앱의 “설정 > Google Cloud API 키” 입력란에 붙여넣고 '
                '“키 저장”을 누르면 됩니다.',
          ),
          _Section(
            title: '6. (선택) 자연스러운 번역용 Gemini 키',
            body: 'Google 정책상 위에서 만든 Cloud 키로는 Gemini를 쓸 수 없습니다. 더 자연스러운 '
                '구어체 번역을 원하면 Google AI Studio에서 “Gemini API” 키를 따로 발급해 '
                '“설정 > Gemini API 키 (선택)” 입력란에 넣으세요. 넣지 않으면 기본 Google '
                '번역으로 자막이 정상 표시됩니다.',
            url: 'https://aistudio.google.com/apikey',
          ),
          _Section(
            title: '비용 안내',
            body: 'Speech-to-Text는 인식한 오디오 “분(minute)” 단위로 과금됩니다. 번역은 '
                'Gemini 키를 넣었으면 Gemini로 자연스럽게 번역하고, 넣지 않았으면 '
                'Cloud Translation(문자 수 단위 과금)을 사용합니다.\n\n'
                '무료 사용량(2026년 6월 기준, 참고용):\n'
                '• 음성 인식: 월 약 60분\n'
                '• 번역: 월 약 500,000자\n\n'
                '무료 한도와 단가는 계정·시점에 따라 달라질 수 있으니 아래 공식 요금 페이지에서 '
                '반드시 확인하세요.\n\n'
                '이 앱의 실시간 자막 모드는 “보고 있는 구간”만 API를 호출하므로 비용을 아낄 수 '
                '있습니다.',
            url: 'https://cloud.google.com/products/calculator',
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
