import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player_screen.dart';
import 'settings_screen.dart';

/// 시작 화면: 로컬 영상 파일 선택 또는 URL 입력.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path != null && mounted) {
      _open(VideoSource.file(path));
    }
  }

  void _openUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    _open(VideoSource.network(url));
  }

  void _open(VideoSource source) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(source: source),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('영상 번역 자막'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '설정',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 16),
            const Text(
              '영상을 선택하면 음성을 인식해 번역 자막을 만들어 드립니다.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'MVP는 60초 이하 클립을 권장합니다.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.video_library),
              label: const Text('영상 파일 선택'),
              onPressed: _pickFile,
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text('또는 영상 URL 입력'),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://example.com/video.mp4',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _openUrl(),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('URL 재생'),
              onPressed: _openUrl,
            ),
          ],
        ),
      ),
    );
  }
}
