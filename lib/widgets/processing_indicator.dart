import 'package:flutter/material.dart';

import '../state/processing_controller.dart';

/// 파이프라인 진행 상태를 보여주는 오버레이.
class ProcessingIndicator extends StatelessWidget {
  const ProcessingIndicator({super.key, required this.state});

  final ProcessingState state;

  String get _label {
    switch (state.status) {
      case ProcessingStatus.extracting:
        return '오디오 추출 중…';
      case ProcessingStatus.recognizing:
        // 긴 영상은 청크 단위 진행률을 함께 표시한다.
        return state.recognizeTotal > 1
            ? '음성 인식 중… (${state.recognizeDone}/${state.recognizeTotal})'
            : '음성 인식 중…';
      case ProcessingStatus.translating:
        return '번역 중…';
      case ProcessingStatus.ready:
        return '자막 준비 완료';
      case ProcessingStatus.error:
        return state.errorMessage ?? '오류가 발생했습니다';
      case ProcessingStatus.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (state.status == ProcessingStatus.idle ||
        state.status == ProcessingStatus.ready) {
      return const SizedBox.shrink();
    }

    final isError = state.status == ProcessingStatus.error;
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!isError) const CircularProgressIndicator(color: Colors.white),
          if (isError)
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
