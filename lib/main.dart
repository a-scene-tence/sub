import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // .env 는 선택 사항(런타임 키 입력도 가능). 없으면 무시.
  try {
    await dotenv.load();
  } catch (_) {
    // .env 파일이 없어도 앱은 동작한다(설정 화면에서 키 입력).
  }
  runApp(const ProviderScope(child: VideoSubtitleTranslatorApp()));
}
