import 'package:flutter/foundation.dart';

/// 웹페이지에서 감지한 재생 가능한 영상의 스트림 종류.
enum VideoStreamKind {
  /// 단일 파일 다운로드형(mp4/webm/mov…). 자막 추출까지 안정적으로 동작.
  progressive,

  /// HLS 매니페스트(m3u8). 재생은 되나 원격 오디오 추출이 제한될 수 있음.
  hls,

  /// MPEG-DASH 매니페스트(mpd). HLS와 동일한 자막 제약.
  dash,

  /// 확장자/MIME로 분류 불가.
  unknown,
}

/// 웹페이지 URL 해석으로 찾아낸 영상 후보 하나.
@immutable
class VideoCandidate {
  const VideoCandidate({
    required this.url,
    required this.kind,
    this.title,
    this.poster,
  });

  /// 재생/추출에 쓸 절대 URL(http/https).
  final String url;

  /// 스트림 종류(progressive 우선).
  final VideoStreamKind kind;

  /// 표시용 제목(og:title 또는 페이지 `<title>`, 없으면 null).
  final String? title;

  /// 썸네일 이미지 URL(og:image 등, 없으면 null).
  final String? poster;

  /// progressive가 아니면 자막 생성이 제한될 수 있다(HLS/DASH 원격 추출 한계).
  bool get subtitleReliable => kind == VideoStreamKind.progressive;

  @override
  bool operator ==(Object other) =>
      other is VideoCandidate &&
      other.url == url &&
      other.kind == kind &&
      other.title == title &&
      other.poster == poster;

  @override
  int get hashCode => Object.hash(url, kind, title, poster);

  @override
  String toString() => 'VideoCandidate($url, $kind)';
}
