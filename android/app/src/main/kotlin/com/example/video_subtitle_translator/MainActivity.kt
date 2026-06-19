package com.example.video_subtitle_translator

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 일부 릴리스 빌드에서 리플렉션 기반 자동 등록이 누락되어 모든 네이티브
        // 플러그인이 MissingPluginException으로 실패하는 문제(9.13) → 명시적 등록으로 보장.
        // 자동 등록이 이미 동작한 경우 중복 add는 엔진 레지스트리가 무시하므로 무해(멱등).
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }
}

