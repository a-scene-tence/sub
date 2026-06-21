import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/subtitle_cue.dart';
import '../providers.dart';
import '../services/cache_cleaner.dart';
import '../state/live_caption_controller.dart';
import '../state/player_controller.dart';
import '../state/settings_controller.dart';
import '../widgets/player_controls.dart';
import '../widgets/subtitle_overlay.dart';
import '../widgets/video_gesture_layer.dart';
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
  LiveCaptionController? _live;
  VideoPlayerController? _videoController;
  bool _initFailed = false;
  String? _initError;
  bool _isFullscreen = false;
  double _videoScale = 1.0; // 핀치 줌(전체화면).
  Offset _videoOffset = Offset.zero; // 줌 상태 팬.
  bool _fillMode = false; // 맞춤 ↔ 꽉 채움.

  // 재생 컨트롤 자동 숨김: 재생 중에는 일정 시간 뒤 숨기고, 화면 탭으로 다시 표시한다.
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final apiKey = await ref.read(secretsProvider).getApiKey();
    // Gemini 전용 키(선택). 없으면 기본 Google 번역으로 동작한다.
    final geminiApiKey = await ref.read(secretsProvider).getGeminiApiKey();
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

    // 실시간 자막 컨트롤러 연결 후 즉시 재생. 자막은 재생을 따라 점진적으로 채워진다.
    final settings = ref.read(settingsProvider).value;
    final live = ref.read(liveCaptionControllerFactory)((
      apiKey: apiKey,
      geminiApiKey: geminiApiKey,
      videoPath: widget.source.path,
      targetLanguage: settings.targetLanguage,
      languageHint: settings.languageHint,
    ));
    live.enabled = settings.liveTranslateEnabled; // 기본 OFF.
    _live = live;
    _player.attach(controller, const <SubtitleCue>[]);
    live.attach(controller, _player);
    live.addListener(_onLiveChanged);
    // 재생/일시정지 전환을 감지해 컨트롤 자동 숨김을 제어한다.
    controller.addListener(_onVideoStateChanged);

    setState(() {});
    await controller.play();
    // 재생 중 화면 꺼짐 방지.
    await WakelockPlus.enable();
  }

  /// 재생↔일시정지 전환 시: 재생하면 잠시 뒤 컨트롤 숨김 예약, 멈추면 컨트롤 표시.
  void _onVideoStateChanged() {
    final playing = _videoController?.value.isPlaying ?? false;
    if (playing == _wasPlaying) return;
    _wasPlaying = playing;
    if (playing) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
      if (mounted) setState(() => _controlsVisible = true);
    }
  }

  /// 재생 중일 때만 일정 시간 후 컨트롤을 자동으로 숨긴다.
  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_videoController?.value.isPlaying ?? false) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  /// 화면 탭: 컨트롤 표시/숨김 토글(표시하면 자동 숨김 타이머 재시작).
  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (!_isFullscreen) {
        // 전체화면 해제 시 확대/팬 리셋(꽉 채움은 일반 모드에서도 쓰므로 유지).
        _videoScale = 1.0;
        _videoOffset = Offset.zero;
      }
      _controlsVisible = true; // 모드 전환 직후엔 컨트롤을 보여준다.
    });
    _scheduleHide();
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    }
  }

  void _toggleFill() {
    setState(() {
      _fillMode = !_fillMode;
      // 비율을 바꾸면 핀치 줌/팬은 초기화(혼란 방지).
      _videoScale = 1.0;
      _videoOffset = Offset.zero;
    });
  }

  void _onLiveChanged() {
    final state = _live?.value;
    if (state != null &&
        state.status == LiveStatus.error &&
        state.errorMessage != null) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(content: Text('실시간 자막 오류: ${state.errorMessage}')),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _videoController?.removeListener(_onVideoStateChanged);
    _live?.removeListener(_onLiveChanged);
    _live?.dispose();

    // 시스템 UI/방향 복원(전체화면 상태로 화면을 떠나도 원복) + 화면 꺼짐 방지 해제.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    WakelockPlus.disable();

    // 영상 컨트롤러 정리 후 file_picker 캐시 사본 삭제(원본은 임시 디렉터리 밖이라 보호됨).
    final localPath = widget.source.isNetwork ? null : widget.source.path;
    _player.dispose().then((_) {
      if (localPath != null) CacheCleaner.deleteIfTemp(localPath);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    // 설정의 토글을 컨트롤러에 동기화(불리언 대입, 멱등 — 다음 tick이 반영).
    _live?.enabled = settings.liveTranslateEnabled;
    final controller = _videoController;

    return Scaffold(
      backgroundColor: Colors.black,
      // 전체화면에서는 AppBar를 숨겨 영상이 화면을 가득 채운다.
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: const Text('재생'),
              actions: <Widget>[
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
            ),
      body: _buildBody(controller, settings),
    );
  }

  Widget _buildBody(VideoPlayerController? controller, AppSettings settings) {
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
    final isWorking = _live?.value.status == LiveStatus.working;

    // 전체 영역을 채우는 Stack: 영상은 가운데에서 확대/축소·팬·핏 적용,
    // 제스처 레이어는 레터박스 위에서도 동작하도록 전체를 덮는다. 하단 컨트롤은
    // 영상 위에 겹쳐 두고, 재생 중에는 자동으로 숨겨 영상을 가리지 않는다.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Center(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translate(_videoOffset.dx, _videoOffset.dy)
              ..scale(_videoScale),
            child: _fillMode
                // SizedBox.expand로 화면 전체 tight 제약을 강제해야 FittedBox가
                // 영상 비율을 유지하지 않고 cover로 화면을 꽉 채워 잘라낸다.
                ? SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox.fromSize(
                        size: controller.value.size,
                        child: VideoPlayer(controller),
                      ),
                    ),
                  )
                : AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
          ),
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
        // 전체 영역을 덮는 제스처 레이어. 한 번 탭하면 컨트롤 표시/숨김 토글.
        Positioned.fill(
          child: VideoGestureLayer(
            controller: controller,
            zoomEnabled: _isFullscreen,
            scale: _videoScale,
            offset: _videoOffset,
            onTap: _toggleControls,
            onZoomChanged: (s, o) => setState(() {
              _videoScale = s;
              _videoOffset = o;
            }),
          ),
        ),
        // 인식 중일 때만 우상단에 작은 표식(차단 오버레이 없음).
        if (isWorking)
          const Positioned(
            top: 8,
            right: 8,
            child: _LiveBadge(),
          ),
        // 하단 재생 컨트롤(자동 숨김). 숨김 상태에선 터치를 통과시켜 탭으로 다시 표시.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              // 하단 시스템 내비게이션 바와 겹치지 않도록 인셋을 확보한다.
              child: SafeArea(
                top: false,
                child: PlayerControls(
                  controller: controller,
                  isFullscreen: _isFullscreen,
                  onToggleFullscreen: _toggleFullscreen,
                  isFill: _fillMode,
                  onToggleFill: _toggleFill,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 실시간 인식 진행 중을 알리는 작은 표식.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.lightBlueAccent,
            ),
          ),
          SizedBox(width: 8),
          Text(
            '실시간 인식 중…',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
