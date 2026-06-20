import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../providers.dart';
import '../state/player_controller.dart';
import '../state/processing_controller.dart';
import '../state/settings_controller.dart';
import '../widgets/player_controls.dart';
import '../widgets/processing_indicator.dart';
import '../widgets/subtitle_overlay.dart';
import 'settings_screen.dart';

/// 영상 소스: 로컬 파일 또는 네트워크 URL.
class VideoSource {
  const VideoSource._(this.path, this.isNetwork);
  factory VideoSource.file(String path) => VideoSource._(path, false);
  factory VideoSource.network(String url) => VideoSource._(url, true);

  final String path;
  final bool isNetwork;
}

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.source});

  final VideoSource source;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  final PlayerController _player = PlayerController();
  ProcessingController? _processing;
  VideoPlayerController? _videoController;
  bool _initFailed = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final apiKey = await ref.read(secretsProvider).getApiKey();
    if (!mounted) return;
    if (apiKey == null) {
      setState(() {
        _initFailed = true;
        _initError = 'API 키가 설정되지 않았습니다. 설정에서 키를 입력하세요.';
      });
      return;
    }

    // 비디오 초기화.
    final controller = widget.source.isNetwork
        ? VideoPlayerController.networkUrl(Uri.parse(widget.source.path))
        : VideoPlayerController.file(File(widget.source.path));
    _videoController = controller;
    try {
      await controller.initialize();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initFailed = true;
        _initError = '영상을 열 수 없습니다: $e';
      });
      return;
    }
    if (!mounted) return;
    setState(() {});

    // 파이프라인 실행.
    final settings = ref.read(settingsProvider).value;
    final processing = ref.read(processingControllerFactory)(apiKey);
    _processing = processing;
    processing.addListener(_onProcessingChanged);
    await processing.process(
      widget.source.path,
      targetLanguage: settings.targetLanguage,
      languageHint: settings.languageHint,
    );
  }

  void _onProcessingChanged() {
    final state = _processing?.value;
    final controller = _videoController;
    if (state == null || controller == null) return;
    if (state.status == ProcessingStatus.ready) {
      _player.attach(controller, state.cues);
      controller.play();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _processing?.removeListener(_onProcessingChanged);
    _processing?.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final controller = _videoController;
    final processingState = _processing?.value ?? const ProcessingState();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('재생'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _buildBody(controller, processingState, settings),
    );
  }

  Widget _buildBody(
    VideoPlayerController? controller,
    ProcessingState processingState,
    AppSettings settings,
  ) {
    if (_initFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _initError ?? '오류',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final bgColor = settings.subtitleBgColor
        .withValues(alpha: settings.subtitleBgOpacity);

    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
                Positioned.fill(
                  child: ValueListenableBuilder(
                    valueListenable: _player.activeCue,
                    builder: (context, cue, _) => SubtitleOverlay(
                      cue: cue,
                      showSource: settings.showSource,
                      fontSize: settings.subtitleFontSize,
                      textColor: settings.subtitleTextColor,
                      backgroundColor: bgColor,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ProcessingIndicator(state: processingState),
                ),
              ],
            ),
          ),
        ),
        // 하단 시스템 내비게이션 바와 겹치지 않도록 인셋을 확보한다.
        SafeArea(
          top: false,
          child: PlayerControls(controller: controller),
        ),
      ],
    );
  }
}
