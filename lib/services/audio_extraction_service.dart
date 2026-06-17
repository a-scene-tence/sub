import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

class AudioExtractionException implements Exception {
  AudioExtractionException(this.message);
  final String message;
  @override
  String toString() => 'AudioExtractionException: $message';
}

/// 오디오 추출 추상 인터페이스(파이프라인 테스트 시 목으로 대체).
abstract class AudioExtractor {
  Future<File> extractWav(String videoPath);
  Future<void> cleanup(File file);
}

/// 영상에서 16kHz mono LINEAR16 WAV 오디오를 추출한다(디바이스 전용, ffmpeg).
///
/// 출력 인코딩은 [AppConfig]의 STT 설정과 정확히 일치해야 한다.
class AudioExtractionService implements AudioExtractor {
  /// [videoPath](로컬 파일 경로 또는 ffmpeg가 읽을 수 있는 URL)에서 WAV를 추출해
  /// 생성된 임시 파일을 반환한다. 호출자는 사용 후 [cleanup]으로 정리한다.
  @override
  Future<File> extractWav(String videoPath) async {
    final tmpDir = await getTemporaryDirectory();
    final outPath = p.join(
      tmpDir.path,
      'audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    final args = <String>[
      '-y', // 덮어쓰기
      '-i', videoPath,
      ...AppConfig.ffmpegAudioArgs,
      outPath,
    ];

    final session = await FFmpegKit.executeWithArguments(args);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw AudioExtractionException(
          '오디오 추출 실패 (code $returnCode): ${logs ?? ''}');
    }

    final file = File(outPath);
    if (!file.existsSync() || file.lengthSync() == 0) {
      throw AudioExtractionException('추출된 오디오 파일이 비어 있음');
    }
    return file;
  }

  /// 추출 임시 파일 정리.
  @override
  Future<void> cleanup(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {/* best-effort */}
  }
}
