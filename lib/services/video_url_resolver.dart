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

    // 응답이 영상 자체면(리다이렉트된 미디어 등) 그대로 1개 후보로. 리다이렉트를 따라간
    // 최종 URL을 후보로 써서 재생 시 헤더 유실/추가 리다이렉트를 줄인다.
    final contentType = (resp.headers['content-type'] ?? '').toLowerCase();
    if (_isMediaContentType(contentType)) {
      final finalUrl = resp.request?.url.toString() ?? uri.toString();
      return <VideoCandidate>[
        VideoCandidate(url: finalUrl, kind: classifyStream(contentType)),
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

/// 미디어 URL 프리플라이트 결과: 리다이렉트를 따라간 최종 URL과 HTTP 상태 코드.
class MediaProbeResult {
  const MediaProbeResult({
    required this.finalUrl,
    required this.statusCode,
    this.contentType,
  });

  final String finalUrl;
  final int statusCode;
  final String? contentType;

  /// 2xx·3xx면 접근 가능으로 본다(3xx는 클라이언트가 따라가지 못한 잔여 리다이렉트).
  bool get ok => statusCode >= 200 && statusCode < 400;

  /// 인증/접근 거부(핫링크 보호 등).
  bool get forbidden => statusCode == 401 || statusCode == 403;
}

/// 재생 전에 미디어 URL을 가볍게 확인한다(베스트에포트). HEAD를 먼저 시도하고, 서버가
/// HEAD를 막으면(405/501 또는 예외) `Range: bytes=0-1` GET으로 폴백한다. 리다이렉트를
/// 따라간 최종 URL과 상태 코드를 돌려준다. 네트워크 오류는 호출자가 처리하도록 그대로 던진다.
Future<MediaProbeResult> probeMediaUrl(
  String url, {
  Map<String, String> headers = const <String, String>{},
  http.Client? client,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final bool ownClient = client == null;
  final http.Client c = client ?? http.Client();
  final Uri uri = Uri.parse(url);
  try {
    http.Response resp;
    try {
      resp = await c.head(uri, headers: headers).timeout(timeout);
      if (resp.statusCode == 405 || resp.statusCode == 501) {
        resp = await _rangeGet(c, uri, headers, timeout);
      }
    } on Exception {
      // HEAD 자체가 막힌 서버 → Range GET으로 폴백(이마저 실패하면 호출자로 전파).
      resp = await _rangeGet(c, uri, headers, timeout);
    }
    return MediaProbeResult(
      finalUrl: resp.request?.url.toString() ?? url,
      statusCode: resp.statusCode,
      contentType: resp.headers['content-type'],
    );
  } finally {
    if (ownClient) c.close();
  }
}

Future<http.Response> _rangeGet(
  http.Client c,
  Uri uri,
  Map<String, String> headers,
  Duration timeout,
) {
  return c
      .get(uri, headers: <String, String>{...headers, 'Range': 'bytes=0-1'})
      .timeout(timeout);
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
  // 후보를 출처 우선순위(priority)·삽입 순서(index)와 함께 모은다. List.sort가 안정 정렬이
  // 아니므로 동일 kind/priority 내 순서는 index로 명시적으로 고정한다.
  final entries = <({VideoCandidate candidate, int priority, int index})>[];

  // priority 0 = 명시적 선언(video/source/og/JSON-LD), 1 = 본문 정규식 폴백.
  void add(String? raw, {String? mime, int priority = 0}) {
    final abs = _absolute(raw, baseUri);
    if (abs == null) return;
    final normalized = _normalizeForDedup(abs);
    if (normalized == null) return;
    if (_isJunkHost(normalized)) return; // 광고·트래커 호스트 제외.
    if (!seen.add(normalized)) return; // fragment 정규화 후 중복 제거.
    entries.add((
      candidate: VideoCandidate(
        url: normalized,
        kind: classifyStream(mime ?? normalized),
        title: title,
        poster: poster,
      ),
      priority: priority,
      index: entries.length,
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

  // 본문 정규식 폴백: 따옴표/공백으로 끝나는 미디어 직링크(명시적 선언보다 후순위).
  final re = RegExp(
    r'''https?:\/\/[^\s"'<>\\]+\.(?:mp4|m3u8|webm|m4v|mov|mkv|mpd)(?:\?[^\s"'<>\\]*)?''',
    caseSensitive: false,
  );
  for (final m in re.allMatches(html)) {
    add(m.group(0), priority: 1);
  }

  // progressive > HLS/DASH > unknown, 동일 kind 내에서는 명시적 선언 우선, 그다음 발견 순서.
  entries.sort((a, b) {
    final byKind = _kindRank(a.candidate.kind).compareTo(_kindRank(b.candidate.kind));
    if (byKind != 0) return byKind;
    final byPriority = a.priority.compareTo(b.priority);
    if (byPriority != 0) return byPriority;
    return a.index.compareTo(b.index);
  });

  final out = entries.map((e) => e.candidate).toList();
  // 정규식 폴백이 과하게 매치되는 페이지를 대비해 상한을 둔다.
  return out.length > _maxCandidates ? out.sublist(0, _maxCandidates) : out;
}

/// 정규식 폴백 폭주를 막기 위한 후보 상한.
const int _maxCandidates = 20;

/// 명백한 광고·트래커 호스트(재생 불가). 오탐을 피해 소수만 유지한다.
const List<String> _junkHosts = <String>[
  'doubleclick.net',
  'googlesyndication.com',
  'google-analytics.com',
  'googletagmanager.com',
  'scorecardresearch.com',
];

/// dedup용 정규화: fragment를 제거한다(Dart Uri가 기본 포트는 파싱 시 정규화).
/// http/https가 아니면 null.
String? _normalizeForDedup(String absUrl) {
  final uri = Uri.tryParse(absUrl);
  if (uri == null || !_isHttp(uri)) return null;
  return uri.removeFragment().toString();
}

/// 호스트가 [_junkHosts]에 속하면(서브도메인 포함) true.
bool _isJunkHost(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return false;
  for (final j in _junkHosts) {
    if (host == j || host.endsWith('.$j')) return true;
  }
  return false;
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
