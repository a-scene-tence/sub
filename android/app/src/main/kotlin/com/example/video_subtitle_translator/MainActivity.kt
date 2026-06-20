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

        // [임시 진단 9.14/9.15] ffmpeg 이벤트 채널 MissingPluginException 원인 캡처.
        // 자막 파이프라인이 flutter.arthenica.com/ffmpeg_kit_event 의 listen 에서 죽는다.
        // ffmpeg 플러그인은 GeneratedPluginRegistrant 등록 목록엔 있으나, 그 등록은
        // onAttachedToEngine 예외를 try/catch 로 로그만 남기고 삼킨다 → 채널 미등록 가능.
        // 자동 등록으로 이미 레지스트리에 들어간 플러그인을 remove 후 다시 add 하여
        // onAttachedToEngine 을 재실행하고, 그때의 실제 예외를 진단 배너가 읽는
        // 동일 파일(filesDir/last_breadcrumb.txt)에 기록한다. 원인 확정용 임시 코드.
        val cls = com.antonkarpenko.ffmpegkit.FFmpegKitFlutterPlugin::class.java
        try {
            flutterEngine.plugins.remove(cls)
        } catch (_: Throwable) { /* best-effort: 재attach 위한 정리 */ }
        try {
            flutterEngine.plugins.add(com.antonkarpenko.ffmpegkit.FFmpegKitFlutterPlugin())
            writeNativeBreadcrumb("ffmpeg 재등록 성공(등록 정상) — 원인은 등록 외부")
        } catch (t: Throwable) {
            writeNativeBreadcrumb("ffmpeg 재등록 실패: ${t.javaClass.name}: ${t.message}")
        }
    }

    /// 네이티브 단계 진단 메시지를 Dart Diagnostics 와 동일한 파일에 기록한다.
    /// getApplicationSupportDirectory() == context.getFilesDir() (path_provider_android)
    /// 이므로 홈 화면 배너가 이 내용을 그대로 표면화한다.
    private fun writeNativeBreadcrumb(msg: String) {
        try {
            val ts = java.text.SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss.SSS", java.util.Locale.US
            ).format(java.util.Date())
            java.io.File(filesDir, "last_breadcrumb.txt").writeText("$ts | native: $msg")
        } catch (_: Throwable) { /* best-effort */ }
    }
}

