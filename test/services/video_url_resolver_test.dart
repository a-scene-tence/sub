import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_subtitle_translator/models/video_candidate.dart';
import 'package:video_subtitle_translator/services/video_url_resolver.dart';

void main() {
  final base = Uri.parse('https://site.example/watch/123');

  group('isDirectMediaUrl', () {
    test('미디어 확장자는 true, 쿼리스트링 무시', () {
      expect(isDirectMediaUrl(Uri.parse('https://x.com/a.mp4')), isTrue);
      expect(isDirectMediaUrl(Uri.parse('https://x.com/a.m3u8?t=9')), isTrue);
      expect(isDirectMediaUrl(Uri.parse('https://x.com/a.MOV')), isTrue);
    });
    test('일반 페이지/비미디어는 false', () {
      expect(isDirectMediaUrl(Uri.parse('https://x.com/watch/1')), isFalse);
      expect(isDirectMediaUrl(Uri.parse('https://x.com/a.html')), isFalse);
      expect(isDirectMediaUrl(Uri.parse('https://x.com/')), isFalse);
    });
  });

  group('classifyStream', () {
    test('확장자/MIME별 분류', () {
      expect(classifyStream('https://x/a.mp4'), VideoStreamKind.progressive);
      expect(classifyStream('https://x/a.m3u8'), VideoStreamKind.hls);
      expect(classifyStream('https://x/a.mpd'), VideoStreamKind.dash);
      expect(classifyStream('video/mp4'), VideoStreamKind.progressive);
      expect(classifyStream('application/vnd.apple.mpegurl'),
          VideoStreamKind.hls);
      expect(classifyStream('https://x/page'), VideoStreamKind.unknown);
    });
  });

  group('parseVideoCandidates', () {
    test('<source> 상대경로 절대화 + progressive', () {
      const html = '<video><source src="/media/clip.mp4" type="video/mp4">'
          '</video>';
      final out = parseVideoCandidates(html, base);
      expect(out, hasLength(1));
      expect(out.first.url, 'https://site.example/media/clip.mp4');
      expect(out.first.kind, VideoStreamKind.progressive);
    });

    test('og:video 메타 + og:title 제목', () {
      const html = '<head>'
          '<meta property="og:title" content="My Clip">'
          '<meta property="og:video:secure_url" '
          'content="https://cdn.example/v.mp4">'
          '</head>';
      final out = parseVideoCandidates(html, base);
      expect(out.map((c) => c.url), contains('https://cdn.example/v.mp4'));
      expect(out.first.title, 'My Clip');
    });

    test('JSON-LD VideoObject.contentUrl 추출', () {
      const html = '<script type="application/ld+json">'
          '{"@type":"VideoObject","contentUrl":"https://cdn.example/ld.mp4"}'
          '</script>';
      final out = parseVideoCandidates(html, base);
      expect(out.map((c) => c.url), contains('https://cdn.example/ld.mp4'));
    });

    test('mp4가 m3u8보다 앞에 정렬되고 중복 제거', () {
      const html = '<video><source src="https://cdn.example/s.m3u8"></video>'
          '<video src="https://cdn.example/p.mp4"></video>'
          '<a href="https://cdn.example/p.mp4">dup</a>';
      final out = parseVideoCandidates(html, base);
      expect(out, hasLength(2)); // 중복 p.mp4 제거.
      expect(out.first.kind, VideoStreamKind.progressive);
      expect(out.last.kind, VideoStreamKind.hls);
    });

    test('영상 없으면 빈 리스트', () {
      const html = '<html><body><p>no video here</p></body></html>';
      expect(parseVideoCandidates(html, base), isEmpty);
    });

    test('정규식 폴백으로 본문 미디어 링크 감지', () {
      const html = '<script>var s="https://cdn.example/inline.mp4?x=1";</script>';
      final out = parseVideoCandidates(html, base);
      expect(out.map((c) => c.url),
          contains('https://cdn.example/inline.mp4?x=1'));
    });
  });

  group('streamHeaders', () {
    test('User-Agent는 항상 포함', () {
      final h = streamHeaders(mediaUrl: 'https://cdn/x.mp4');
      expect(h['User-Agent'], isNotNull);
      expect(h.containsKey('Referer'), isFalse);
    });
    test('pageUrl이 다르면 Referer + Origin 포함', () {
      final h = streamHeaders(
          mediaUrl: 'https://cdn/x.mp4', pageUrl: 'https://site/watch');
      expect(h['Referer'], 'https://site/watch');
      expect(h['Origin'], 'https://site');
    });
    test('Origin은 포트가 있으면 포트까지 포함', () {
      final h = streamHeaders(
          mediaUrl: 'https://cdn/x.mp4', pageUrl: 'https://site:8443/watch');
      expect(h['Origin'], 'https://site:8443');
    });
    test('pageUrl == mediaUrl이면 Referer/Origin 없음', () {
      final h = streamHeaders(
          mediaUrl: 'https://cdn/x.mp4', pageUrl: 'https://cdn/x.mp4');
      expect(h.containsKey('Referer'), isFalse);
      expect(h.containsKey('Origin'), isFalse);
    });
  });

  group('VideoUrlResolver.resolve', () {
    test('직접 mp4 URL은 네트워크 호출 없이 1개 후보', () async {
      var called = false;
      final resolver = VideoUrlResolver(client: MockClient((_) async {
        called = true;
        return http.Response('', 200);
      }));
      final out = await resolver.resolve('https://x.com/a.mp4');
      expect(called, isFalse);
      expect(out, hasLength(1));
      expect(out.first.kind, VideoStreamKind.progressive);
    });

    test('HTML 페이지에서 후보 다수 추출', () async {
      final resolver = VideoUrlResolver(client: MockClient((_) async {
        return http.Response(
          '<video src="https://cdn/p.mp4"></video>'
          '<video><source src="https://cdn/s.m3u8"></video>',
          200,
          headers: const <String, String>{'content-type': 'text/html'},
        );
      }));
      final out = await resolver.resolve('https://site.example/watch');
      expect(out.length, greaterThanOrEqualTo(2));
    });

    test('비-http scheme는 거부', () async {
      final resolver = VideoUrlResolver(client: MockClient((_) async {
        return http.Response('', 200);
      }));
      expect(
        () => resolver.resolve('ftp://x.com/a.mp4'),
        throwsA(isA<ResolveException>()),
      );
    });

    test('영상 없는 페이지는 예외', () async {
      final resolver = VideoUrlResolver(client: MockClient((_) async {
        return http.Response('<p>nothing</p>', 200,
            headers: const <String, String>{'content-type': 'text/html'});
      }));
      expect(
        () => resolver.resolve('https://site.example/empty'),
        throwsA(isA<ResolveException>()),
      );
    });
  });
}
