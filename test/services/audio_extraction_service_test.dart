import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:video_subtitle_translator/services/audio_extraction_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel =
      MethodChannel('plugins.flutter.io/path_provider');
  final audioChannel = MethodChannel('test/audio_${identityHashCode(main)}');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('audio_ext_test');
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tmp.path;
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    messenger.setMockMethodCallHandler(audioChannel, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('extractWav: 채널 호출 인자 전달 + 성공 시 File 반환', () async {
    Map<dynamic, dynamic>? receivedArgs;
    messenger.setMockMethodCallHandler(audioChannel, (call) async {
      expect(call.method, 'extractWav');
      receivedArgs = call.arguments as Map<dynamic, dynamic>;
      // 네이티브가 outPath에 WAV를 쓰는 것을 흉내낸다.
      File(receivedArgs!['outPath'] as String).writeAsBytesSync(
          List<int>.filled(100, 0));
      return <String, dynamic>{
        'sampleRate': 48000,
        'channels': 1,
        'durationMs': 1000,
      };
    });

    final service = AudioExtractionService(channel: audioChannel);
    final file = await service.extractWav('/video/in.mp4');

    expect(receivedArgs!['videoPath'], '/video/in.mp4');
    expect(receivedArgs!['outPath'], startsWith(tmp.path));
    expect(p.extension(file.path), '.wav');
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), 100);
  });

  test('extractWav: 빈 파일이면 AudioExtractionException', () async {
    messenger.setMockMethodCallHandler(audioChannel, (call) async {
      // outPath에 파일을 만들지 않음(빈 결과 시뮬레이션).
      return <String, dynamic>{'sampleRate': 16000};
    });

    final service = AudioExtractionService(channel: audioChannel);
    await expectLater(
      service.extractWav('/video/in.mp4'),
      throwsA(isA<AudioExtractionException>()),
    );
  });

  test('extractWav: 네이티브 PlatformException → AudioExtractionException', () async {
    messenger.setMockMethodCallHandler(audioChannel, (call) async {
      throw PlatformException(code: 'extract_failed', message: '오디오 트랙 없음');
    });

    final service = AudioExtractionService(channel: audioChannel);
    await expectLater(
      service.extractWav('/video/in.mp4'),
      throwsA(isA<AudioExtractionException>()
          .having((e) => e.message, 'message', contains('오디오 트랙 없음'))),
    );
  });

  test('cleanup: 파일 삭제', () async {
    final f = File(p.join(tmp.path, 'x.wav'))..writeAsBytesSync(<int>[1]);
    final service = AudioExtractionService(channel: audioChannel);
    await service.cleanup(f);
    expect(f.existsSync(), isFalse);
  });
}
