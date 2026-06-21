import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:video_subtitle_translator/services/cache_cleaner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tmp; // 모의 임시(캐시) 디렉터리.
  late Directory outside; // 임시 디렉터리 밖(사용자 원본 흉내).

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cache_test_tmp');
    outside = await Directory.systemTemp.createTemp('cache_test_out');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tmp.path;
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    if (outside.existsSync()) outside.deleteSync(recursive: true);
  });

  File writeFile(String path, int bytes) {
    final f = File(path)..createSync(recursive: true);
    f.writeAsBytesSync(List<int>.filled(bytes, 0));
    return f;
  }

  group('deleteIfTemp', () {
    test('임시 디렉터리 내부 파일은 삭제', () async {
      final f = writeFile(p.join(tmp.path, 'file_picker', 'video.mp4'), 10);
      await CacheCleaner.deleteIfTemp(f.path);
      expect(f.existsSync(), isFalse);
    });

    test('임시 디렉터리 밖 경로(원본)는 삭제하지 않음', () async {
      final f = writeFile(p.join(outside.path, 'my_video.mp4'), 10);
      await CacheCleaner.deleteIfTemp(f.path);
      expect(f.existsSync(), isTrue);
    });
  });

  group('purgeOnStartup / clearCache', () {
    test('audio_*.wav와 file_picker/ 만 지우고 나머지는 보존', () async {
      final wav = writeFile(p.join(tmp.path, 'audio_123.wav'), 10);
      final picked = writeFile(p.join(tmp.path, 'file_picker', 'v.mp4'), 10);
      final keep = writeFile(p.join(tmp.path, 'google_api_key.txt'), 10);
      final other = writeFile(p.join(tmp.path, 'note.txt'), 10);

      await CacheCleaner.purgeOnStartup();

      expect(wav.existsSync(), isFalse);
      expect(Directory(p.join(tmp.path, 'file_picker')).existsSync(), isFalse);
      expect(picked.existsSync(), isFalse);
      expect(keep.existsSync(), isTrue); // API 키 폴백 보존.
      expect(other.existsSync(), isTrue);
    });
  });

  group('cacheSizeBytes', () {
    test('임시 디렉터리 내 파일 크기 합산', () async {
      writeFile(p.join(tmp.path, 'audio_1.wav'), 100);
      writeFile(p.join(tmp.path, 'file_picker', 'v.mp4'), 250);
      expect(await CacheCleaner.cacheSizeBytes(), 350);
    });
  });

  group('formatBytes', () {
    test('사람이 읽기 쉬운 단위', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });
}
