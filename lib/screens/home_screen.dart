import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_candidate.dart';
import '../providers.dart';
import '../services/diagnostics.dart';
import '../services/video_url_resolver.dart';
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
  bool _resolving = false;

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

  /// URL 입력 흐름: 직접 미디어 URL이면 바로, 일반 웹페이지면 영상 파일을 감지해 재생한다.
  /// 후보가 여러 개면 선택 시트를 띄운다.
  Future<void> _openUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _resolving) return;

    setState(() => _resolving = true);
    final messenger = ScaffoldMessenger.of(context);
    List<VideoCandidate> candidates;
    try {
      candidates = await ref.read(videoUrlResolverProvider).resolve(url);
    } on ResolveException catch (e) {
      if (!mounted) return;
      setState(() => _resolving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _resolving = false);
      messenger.showSnackBar(SnackBar(content: Text('영상을 찾지 못했습니다: $e')));
      return;
    }
    if (!mounted) return;
    setState(() => _resolving = false);

    if (candidates.length == 1) {
      _playCandidate(candidates.first);
      return;
    }
    final chosen = await _pickCandidate(candidates);
    if (chosen != null) _playCandidate(chosen);
  }

  /// 여러 후보 중 하나를 고르는 모달 바텀시트.
  Future<VideoCandidate?> _pickCandidate(List<VideoCandidate> candidates) {
    return showModalBottomSheet<VideoCandidate>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('재생할 영상 선택',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (context, i) {
                    final c = candidates[i];
                    return ListTile(
                      leading: const Icon(Icons.movie_outlined),
                      title: Text(
                        c.title?.isNotEmpty == true ? c.title! : c.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        c.subtitleReliable
                            ? c.url
                            : '${c.url}\n스트림 영상 — 자막이 제한될 수 있어요',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: !c.subtitleReliable,
                      onTap: () => Navigator.of(context).pop(c),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _playCandidate(VideoCandidate c) {
    if (!c.subtitleReliable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('스트림(HLS/DASH) 영상이라 자막 생성이 제한될 수 있어요.'),
        ),
      );
    }
    _open(VideoSource.network(c.url));
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
              '긴 영상도 지원합니다. 다만 영상이 길수록 인식·번역 처리 시간이 늘어납니다.',
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
            const SizedBox(height: 4),
            const Text(
              '영상 파일 URL은 물론, 영상이 있는 웹페이지 주소를 넣으면 영상을 찾아 재생합니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              enabled: !_resolving,
              decoration: const InputDecoration(
                hintText: 'https://example.com/page 또는 video.mp4',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _openUrl(),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: _resolving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_circle_outline),
              label: Text(_resolving ? '영상 찾는 중…' : 'URL 재생'),
              onPressed: _resolving ? null : _openUrl,
            ),
          ],
        ),
      ),
    );
  }
}
