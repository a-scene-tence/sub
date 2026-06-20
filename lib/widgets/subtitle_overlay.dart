import 'package:flutter/material.dart';

import '../models/subtitle_cue.dart';

/// 영상 위에 떠 있는 자막. [cue]가 null이면 아무것도 그리지 않는다.
///
/// 글자 크기/색/배경색은 설정에서 주입한다([backgroundColor]는 투명도가 이미 반영된 값).
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    super.key,
    required this.cue,
    this.showSource = false,
    this.fontSize = 20,
    this.textColor = Colors.white,
    this.backgroundColor = const Color(0x99000000),
  });

  final SubtitleCue? cue;

  /// true면 원문도 함께 작게 표시.
  final bool showSource;

  /// 번역 자막 글자 크기. 원문은 이 값의 0.7배로 표시.
  final double fontSize;

  /// 번역 자막 글자색. 원문은 약간 흐리게 표시.
  final Color textColor;

  /// 자막 배경색(투명도 반영 완료).
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final cue = this.cue;
    if (cue == null || cue.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 32, left: 16, right: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showSource && (cue.sourceText?.isNotEmpty ?? false))
              _SubtitleText(
                text: cue.sourceText!,
                fontSize: fontSize * 0.7,
                color: textColor.withValues(alpha: 0.7),
                backgroundColor: backgroundColor,
              ),
            _SubtitleText(
              text: cue.text,
              fontSize: fontSize,
              color: textColor,
              backgroundColor: backgroundColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubtitleText extends StatelessWidget {
  const _SubtitleText({
    required this.text,
    required this.fontSize,
    required this.color,
    required this.backgroundColor,
  });

  final String text;
  final double fontSize;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}
