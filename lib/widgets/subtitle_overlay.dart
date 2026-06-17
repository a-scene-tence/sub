import 'package:flutter/material.dart';

import '../models/subtitle_cue.dart';

/// 영상 위에 떠 있는 자막. [cue]가 null이면 아무것도 그리지 않는다.
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay(
      {super.key, required this.cue, this.showSource = false});

  final SubtitleCue? cue;

  /// true면 원문도 함께 작게 표시.
  final bool showSource;

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
                fontSize: 14,
                color: Colors.white70,
              ),
            _SubtitleText(text: cue.text, fontSize: 20, color: Colors.white),
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
  });

  final String text;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
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
