import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/diagnostics.dart';
import '../theme/app_theme.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

/// 시작 화면: 로컬 영상 파일을 선택한다(에디토리얼 표지 톤).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 직전 실행이 비정상 종료(네이티브 크래시 등)했다면 마지막 브레드크럼을 표면화한다.
    // 정상 완료 시 파이프라인이 clear() 하므로, 배너는 멈춘 적이 있을 때만 뜬다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showLastCrumb());
  }

  Future<void> _showLastCrumb() async {
    final crumb = await Diagnostics.read();
    if (crumb == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text('이전 실행 기록: $crumb'),
        leading: const Icon(Icons.history),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              Diagnostics.clear();
            },
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path != null && mounted) {
      _open(VideoSource.file(path));
    }
  }

  void _open(VideoSource source) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerScreen(source: source)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 28,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 8),
              Text(
                '인프레임',
                style: textTheme.displayLarge?.copyWith(
                  fontSize: 52,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 22),
              Container(height: 1, color: AppPalette.hairline),
              const SizedBox(height: 22),
              Text(
                '영상을 선택하면 음성을 인식해\n자연스러운 번역 자막을 만들어 드려요.',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                  color: AppPalette.inkSoft,
                ),
              ),
              const Spacer(),
              _PickAction(onTap: _pickFile),
              const SizedBox(height: 16),
              Text(
                '긴 영상도 지원합니다. 다만 영상이 길수록 인식·번역 처리 시간이 늘어납니다.',
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 전체 폭 액션 블록(라벨 좌측 + 화살표 우측).
class _PickAction extends StatelessWidget {
  const _PickAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('영상 파일 선택'),
            Icon(Icons.arrow_forward, size: 20),
          ],
        ),
      ),
    );
  }
}
