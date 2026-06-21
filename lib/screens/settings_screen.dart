import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../providers.dart';
import '../services/language_codes.dart';
import '../state/settings_controller.dart';

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
    try {
      await ref.read(secretsProvider).setApiKey(key);
      ref.invalidate(apiKeyProvider);
      if (!mounted) return;
      _keyController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API 키를 저장했습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('키 저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
          SwitchListTile(
            title: const Text('실시간 자막 번역'),
            subtitle: const Text('재생 중 보고 있는 구간만 인식·번역(API 비용 절약)'),
            value: current.liveTranslateEnabled,
            onChanged: settings.setLiveTranslateEnabled,
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 40),
          const Text('자막 스타일', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _StylePreview(settings: current),
          const SizedBox(height: 16),
          Text('글자 크기: ${current.subtitleFontSize.round()}'),
          Slider(
            value: current.subtitleFontSize.clamp(14, 36),
            min: 14,
            max: 36,
            divisions: 22,
            label: current.subtitleFontSize.round().toString(),
            onChanged: settings.setSubtitleFontSize,
          ),
          const SizedBox(height: 8),
          const Text('글자색'),
          const SizedBox(height: 8),
          _ColorSwatchRow(
            colors: _textColors,
            selected: current.subtitleTextColor,
            onSelected: settings.setSubtitleTextColor,
          ),
          const SizedBox(height: 16),
          const Text('배경색'),
          const SizedBox(height: 8),
          _ColorSwatchRow(
            colors: _bgColors,
            selected: current.subtitleBgColor,
            onSelected: settings.setSubtitleBgColor,
          ),
          const SizedBox(height: 16),
          Text('배경 투명도: ${(current.subtitleBgOpacity * 100).round()}%'),
          Slider(
            value: current.subtitleBgOpacity.clamp(0, 1),
            divisions: 20,
            label: '${(current.subtitleBgOpacity * 100).round()}%',
            onChanged: settings.setSubtitleBgOpacity,
          ),
        ],
      ),
    );
  }
}

/// 글자색 프리셋(흰/노랑/하늘/연두/주황/검정).
const List<Color> _textColors = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFFFFEB3B),
  Color(0xFF40C4FF),
  Color(0xFF69F0AE),
  Color(0xFFFF9800),
  Color(0xFF000000),
];

/// 배경색 프리셋(검정/짙은회색/남색/적갈색/흰색).
const List<Color> _bgColors = <Color>[
  Color(0xFF000000),
  Color(0xFF424242),
  Color(0xFF1A237E),
  Color(0xFF3E2723),
  Color(0xFFFFFFFF),
];

/// 현재 자막 스타일 미리보기.
class _StylePreview extends StatelessWidget {
  const _StylePreview({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        // 영상 위 느낌을 주기 위한 회색 바탕.
        color: Colors.grey.shade700,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: settings.subtitleBgColor
              .withValues(alpha: settings.subtitleBgOpacity),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '자막 미리보기 예시',
          style: TextStyle(
            color: settings.subtitleTextColor,
            fontSize: settings.subtitleFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 원형 색상 스와치 선택 행.
class _ColorSwatchRow extends StatelessWidget {
  const _ColorSwatchRow({
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        for (final c in colors)
          Builder(builder: (context) {
            final isSelected = c == selected;
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onSelected(c),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade400,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: c.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                      )
                    : null,
              ),
            );
          }),
      ],
    );
  }
}
