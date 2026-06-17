import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../providers.dart';
import '../services/language_codes.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    setState(() => _saving = true);
    await ref.read(secretsProvider).setApiKey(key);
    ref.invalidate(apiKeyProvider);
    if (!mounted) return;
    setState(() => _saving = false);
    _keyController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API 키를 저장했습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final current = settings.value;
    final hasKey = ref.watch(apiKeyProvider).valueOrNull != null;

    // 대상 언어 후보(언어명 표시).
    const targets = <String>['ko', 'en', 'ja', 'zh', 'es', 'fr', 'de'];

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('Google Cloud API 키',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            hasKey ? '키가 저장되어 있습니다.' : '키가 설정되지 않았습니다.',
            style: TextStyle(color: hasKey ? Colors.green : Colors.red),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _keyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API 키 입력',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _saveKey,
            child: Text(_saving ? '저장 중…' : '키 저장'),
          ),
          const Divider(height: 40),
          const Text('번역 대상 언어', style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButton<String>(
            value: current.targetLanguage,
            isExpanded: true,
            items: <DropdownMenuItem<String>>[
              for (final code in targets)
                DropdownMenuItem<String>(
                  value: code,
                  child: Text(languageDisplayName(code)),
                ),
            ],
            onChanged: (v) {
              if (v != null) settings.setTargetLanguage(v);
            },
          ),
          const SizedBox(height: 16),
          const Text('소스 언어(자동 감지 기본)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButton<String?>(
            value: current.languageHint,
            isExpanded: true,
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                child: Text('자동 감지'),
              ),
              for (final code in AppConfig.languageCandidates)
                DropdownMenuItem<String?>(
                  value: code,
                  child: Text(code),
                ),
            ],
            onChanged: settings.setLanguageHint,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('원문 함께 표시'),
            value: current.showSource,
            onChanged: settings.setShowSource,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
