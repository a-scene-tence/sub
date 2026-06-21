import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 영상→16-bit mono PCM WAV 추출(폐기된 FFmpegKit 대체). AVAssetReader 사용.
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.example.video_subtitle_translator/audio",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "extractWav":
          guard
            let args = call.arguments as? [String: Any],
            let videoPath = args["videoPath"] as? String,
            let outPath = args["outPath"] as? String,
            !videoPath.isEmpty, !outPath.isEmpty
          else {
            result(FlutterError(code: "bad_args", message: "videoPath/outPath 필요", details: nil))
            return
          }
          // startMs/endMs가 있으면 해당 구간만 추출(실시간 자막용), 없으면 전체.
          let startMs = args["startMs"] as? Int
          let endMs = args["endMs"] as? Int
          AudioExtractor.extractWavAsync(
            videoPath: videoPath, outPath: outPath,
            startMs: startMs, endMs: endMs, result: result
          )
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
