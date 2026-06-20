package com.example.video_subtitle_translator

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // [임시 진단 9.16] FFmpegKitConfig 정적 초기화(<clinit>) 실패의 근본 원인 캡처.
        // 자막 파이프라인이 NoClassDefFoundError: ...FFmpegKitConfig 로 죽는다(9.15). .so/클래스는
        // APK에 있고 R8도 꺼져 있어, 실제 사유는 <clinit> 최초 로드 시의 ExceptionInInitializerError
        // (그 cause: 예 UnsatisfiedLinkError dlopen/16KB)에 있다. 자동 플러그인 등록(super 이후)이
        // 최초 로드를 먼저 트리거하면 원본 예외가 삼켜지므로, super 호출 전에 우리가 직접 로드해
        // 원인 체인을 진단 배너 파일(filesDir/last_breadcrumb.txt)에 기록한다.
        captureFFmpegInit()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 일부 릴리스 빌드에서 리플렉션 기반 자동 등록이 누락되어 모든 네이티브
        // 플러그인이 MissingPluginException으로 실패하는 문제(9.13) → 명시적 등록으로 보장.
        // 자동 등록이 이미 동작한 경우 중복 add는 엔진 레지스트리가 무시하므로 무해(멱등).
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }

    /// FFmpegKitConfig 를 직접 로드(initialize=true)해 최초 <clinit> 를 트리거하고,
    /// 실패 시 원본 예외의 cause 체인을 한 줄로 기록한다. 원인 확정용 임시 진단 코드.
    private fun captureFFmpegInit() {
        try {
            Class.forName("com.antonkarpenko.ffmpegkit.FFmpegKitConfig")
            writeNativeBreadcrumb("FFmpegKitConfig 초기화 성공")
        } catch (t: Throwable) {
            val sb = StringBuilder("FFmpegKitConfig 초기화 실패: ")
            var e: Throwable? = t
            var depth = 0
            while (e != null && depth < 6) {
                sb.append(e!!.javaClass.simpleName).append(": ").append(e!!.message ?: "")
                e = e!!.cause
                if (e != null) sb.append(" <= ")
                depth++
            }
            writeNativeBreadcrumb(sb.toString())
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
