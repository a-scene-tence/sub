import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/video_candidate.dart';

/// URL 해석 실패(잘못된 주소·네트워크 오류·영상 미발견)를 알리는 예외.
class ResolveException implements Exception {
  ResolveException(this.message);
  final String message;
  @override
  String toString() => 'ResolveException: $message';
}

/// 입력 URL을 재생 가능한 영상 후보 목록으로 해석한다.
///
/// 직접 미디어 URL(.mp4 등)은 네트워크 호출 없이 그대로 1개 후보로 반환하고, 일반 웹페이지는
/// HTML을 받아 `<video>`/`og:video`/JSON-LD 등에서 영상을 찾아낸다. JS로만 영상을 로드하는
/// 사이트(YouTube 등)는 정적 HTML에 영상이 없어 빈 결과가 되며, 호출자가 안내한다.
class VideoUrlResolver {
  VideoUrlResolver({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<VideoCandidate>> resolve(String input) async {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !_isHttp(uri)) {
      throw ResolveException('http/https로 시작하는 URL을 입력하세요.');
    }

    // 이미 직접 미디어 링크면 네트워크 호출 없이 즉시 반환(기존 동작 보존).
    if (isDirectMediaUrl(uri)) {
      return <VideoCandidate>[
        VideoCandidate(url: uri.toString(), kind: classifyStream(uri.toString())),
      ];
    }

    final http.Response resp;
    try {
      resp = await _client.get(
        uri,
        headers: const <String, String>{
          'User-Agent': AppConfig.webFetchUserAgent,
          'Accept': 'text/html,application/xhtml+xml,*/*',
        },
      ).timeout(AppConfig.webFetchTimeout);
    } catch (e) {
      throw ResolveException('페이지를 불러오지 못했습니다: $e');
    }

    if (resp.statusCode != 200) {
      throw ResolveException('페이지를 불러오지 못했습니다 (HTTP ${resp.statusCode}).');
    }

    // 응답이 영상 자체면(리다이렉트된 미디어 등) 그대로 1개 후보로.
    final contentType = (resp.headers['content-type'] ?? '').toLowerCase();
    if (_isMediaContentType(contentType)) {
      return <VideoCandidate>[
        VideoCandidate(url: uri.toString(), kind: classifyStream(contentType)),
      ];
    }

    var body = resp.body;
    if (body.length > AppConfig.webFetchMaxBytes) {
      body = body.substring(0, AppConfig.webFetchMaxBytes);
    }
    final candidates = parseVideoCandidates(body, uri);
    if (candidates.isEmpty) {
      throw ResolveException('이 페이지에서 영상을 찾지 못했습니다.');
    }
    return candidates;
  }
}

/// 미디어 요청에 붙일 HTTP 헤더. User-Agent는 항상, Referer/Origin은 영상이 어떤 페이지에서
/// 발견된 경우에만 추가한다(핫링크 보호 우회). 직접 미디어 URL 입력은 [pageUrl]을 주지 않는다.
///
/// Referer만으로 통과되지 않고 Origin(스킴+호스트[:포트])을 함께 검사하는 CDN이 있어
/// 페이지 출처가 확인되면 Origin도 같이 보낸다.
Map<String, String> streamHeaders({required String mediaUrl, String? pageUrl}) {
  final h = <String, String>{'User-Agent': AppConfig.webFetchUserAgent};
  if (pageUrl != null && pageUrl.isNotEmpty && pageUrl != mediaUrl) {
    h['Referer'] = pageUrl;
    final page = Uri.tryParse(pageUrl);
    if (page != null && _isHttp(page) && page.host.isNotEmpty) {
      h['Origin'] = page.hasPort
          ? '${page.scheme}://${page.host}:${page.port}'
          : '${page.scheme}://${page.host}';
    }
  }
  return h;
}

bool _isHttp(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

bool _isMediaContentType(String contentType) =>
    contentType.startsWith('video/') ||
    contentType.contains('mpegurl') || // HLS (application/vnd.apple.mpegurl)
    contentType.contains('dash+xml'); // DASH

/// URL 경로 확장자가 미디어 파일이면 true(쿼리스트링은 무시).
bool isDirectMediaUrl(Uri url) {
  final ext = _extensionOf(url.path);
  return ext != null && AppConfig.mediaFileExtensions.contains(ext);
}

/// 확장자 또는 MIME 문자열로 스트림 종류를 분류한다.
VideoStreamKind classifyStream(String urlOrMime) {
  final s = urlOrMime.toLowerCase();
  if (s.contains('m3u8') || s.contains('mpegurl')) return VideoStreamKind.hls;
  if (s.contains('.mpd') || s.contains('dash+xml')) return VideoStreamKind.dash;
  if (s.startsWith('video/')) return VideoStreamKind.progressive;
  final ext = _extensionOf(Uri.tryParse(s)?.path ?? s);
  if (ext != null && AppConfig.mediaFileExtensions.contains(ext)) {
    if (ext == 'm3u8') return VideoStreamKind.hls;
    if (ext == 'mpd') return VideoStreamKind.dash;
    return VideoStreamKind.progressive;
  }
  return VideoStreamKind.unknown;
}

/// HTML에서 영상 후보를 추출한다(순수 함수). 상대 URL은 [baseUri] 기준으로 절대화하고,
/// 중복을 제거하며, progressive(mp4 등)를 HLS/DASH보다 앞에 정렬한다.
List<VideoCandidate> parseVideoCandidates(String html, Uri baseUri) {
  final dom.Document doc = html_parser.parse(html);

  final title = _metaContent(doc, property: 'og:title') ??
      doc.querySelector('title')?.text.trim();
  final poster = _absolute(_metaContent(doc, property: 'og:image'), baseUri);

  final seen = <String>{};
  final out = <VideoCandidate>[];

  void add(String? raw, {String? mime}) {
    final abs = _absolute(raw, baseUri);
    if (abs == null) return;
    if (!seen.add(abs)) return;
    out.add(VideoCandidate(
      url: abs,
      kind: classifyStream(mime ?? abs),
      title: title,
      poster: poster,
    ));
  }

  // <video src> 및 <video><source src type>
  for (final v in doc.querySelectorAll('video[src]')) {
    add(v.attributes['src']);
  }
  for (final s in doc.querySelectorAll('video source[src]')) {
    add(s.attributes['src'], mime: s.attributes['type']);
  }

  // Open Graph / Twitter player 메타.
  for (final p in const <String>[
    'og:video',
    'og:video:url',
    'og:video:secure_url',
  ]) {
    add(_metaContent(doc, property: p));
  }
  add(_metaContent(doc, name: 'twitter:player:stream'));

  // JSON-LD VideoObject.contentUrl.
  for (final node in doc.querySelectorAll('script[type="application/ld+json"]')) {
    _collectJsonLdContentUrls(node.text, add);
  }

  // 본문 정규식 폴백: 따옴표/공백으로 끝나는 미디어 직링크.
  final re = RegExp(
    r'''https?:\/\/[^\s"'<>\\]+\.(?:mp4|m3u8|webm|m4v|mov|mkv|mpd)(?:\?[^\s"'<>\\]*)?''',
    caseSensitive: false,
  );
  for (final m in re.allMatches(html)) {
    add(m.group(0));
  }

  out.sort((a, b) => _kindRank(a.kind).compareTo(_kindRank(b.kind)));
  return out;
}

int _kindRank(VideoStreamKind k) {
  switch (k) {
    case VideoStreamKind.progressive:
      return 0;
    case VideoStreamKind.hls:
    case VideoStreamKind.dash:
      return 1;
    case VideoStreamKind.unknown:
      return 2;
  }
}

void _collectJsonLdContentUrls(String json, void Function(String?) add) {
  Object? decoded;
  try {
    decoded = jsonDecode(json);
  } catch (_) {
    return;
  }
  void walk(Object? node) {
    if (node is Map) {
      final cu = node['contentUrl'] ?? node['contentURL'];
      if (cu is String) add(cu);
      for (final v in node.values) {
        walk(v);
      }
    } else if (node is List) {
      for (final v in node) {
        walk(v);
      }
    }
  }

  walk(decoded);
}

String? _metaContent(dom.Document doc, {String? property, String? name}) {
  final selector = property != null
      ? 'meta[property="$property"]'
      : 'meta[name="$name"]';
  final content = doc.querySelector(selector)?.attributes['content']?.trim();
  return (content == null || content.isEmpty) ? null : content;
}

/// [raw]를 [base] 기준 절대 URL로 만든다. http/https가 아니거나 파싱 불가면 null.
String? _absolute(String? raw, Uri base) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final resolved = base.tryResolve(trimmed);
  if (resolved == null || !_isHttp(resolved)) return null;
  return resolved.toString();
}

/// 경로의 소문자 확장자(점 제외). 없으면 null.
String? _extensionOf(String path) {
  final lastSlash = path.lastIndexOf('/');
  final segment = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
  final dot = segment.lastIndexOf('.');
  if (dot < 0 || dot == segment.length - 1) return null;
  return segment.substring(dot + 1).toLowerCase();
}

extension on Uri {
  /// `resolve`의 throw-안전 버전.
  Uri? tryResolve(String ref) {
    try {
      return resolve(ref);
    } catch (_) {
      return null;
    }
  }
}
