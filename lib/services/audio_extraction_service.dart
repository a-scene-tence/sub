import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// 영상에서 16-bit mono PCM WAV 오디오를 추출한다(디바이스 전용, 플랫폼 네이티브).
///
/// Android는 `MediaExtractor`+`MediaCodec`, iOS는 `AVAssetReader`로 디코드한다(폐기된
/// FFmpegKit 제거). 샘플레이트는 소스 네이티브 레이트를 유지하고, WAV 헤더에 기록한다.
/// STT는 그 헤더에서 실제 레이트를 읽으므로 별도 리샘플링은 하지 않는다.
class AudioExtractionService implements AudioExtractor {
  AudioExtractionService({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
                'com.example.video_subtitle_translator/audio');

  final MethodChannel _channel;

  /// [videoPath](로컬 파일 경로 또는 http(s) URL)에서 WAV를 추출해 생성된 임시 파일을
  /// 반환한다. 호출자는 사용 후 [cleanup]으로 정리한다.
  @override
  Future<File> extractWav(String videoPath) async {
    final tmpDir = await getTemporaryDirectory();
    final outPath = p.join(
      tmpDir.path,
      'audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    try {
      await _channel.invokeMethod<Map<dynamic, dynamic>>('extractWav', {
        'videoPath': videoPath,
        'outPath': outPath,
      });
    } on PlatformException catch (e) {
      throw AudioExtractionException('오디오 추출 실패: ${e.message ?? e.code}');
    } on MissingPluginException {
      throw AudioExtractionException('오디오 추출 기능을 사용할 수 없습니다(미지원 플랫폼).');
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
