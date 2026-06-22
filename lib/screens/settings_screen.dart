import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../providers.dart';
import '../services/cache_cleaner.dart';
import '../services/language_codes.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import 'api_key_guide_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _geminiKeyController = TextEditingController();
  bool _savingGemini = false;
  int? _cacheBytes; // null = 계산 중.
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  @override
  void dispose() {
    _geminiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadCacheSize() async {
    final bytes = await CacheCleaner.cacheSizeBytes();
    if (mounted) setState(() => _cacheBytes = bytes);
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      await CacheCleaner.clearCache();
      await _loadCacheSize();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('캐시를 비웠습니다.')),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  /// Gemini 키 저장. 입력이 비어 있으면 저장된 키를 제거한다.
  Future<void> _saveGeminiKey() async {
    final key = _geminiKeyController.text.trim();
    setState(() => _savingGemini = true);
    try {
      final secrets = ref.read(secretsProvider);
      if (key.isEmpty) {
        await secrets.clearGeminiApiKey();
      } else {
        await secrets.setGeminiApiKey(key);
      }
      ref.invalidate(geminiApiKeyProvider);
      if (!mounted) return;
      _geminiKeyController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(key.isEmpty ? 'Gemini 키를 제거했습니다.' : 'Gemini 키를 저장했습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gemini 키 저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingGemini = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final current = settings.value;
    final hasGeminiKey = ref.watch(geminiApiKeyProvider).valueOrNull != null;

    // 대상 언어 후보(언어명 표시).
    const targets = <String>['ko', 'en', 'ja', 'zh', 'es', 'fr', 'de'];

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(28, 12, 24, 48),
        children: <Widget>[
          const _SectionHeader(
            'API 키',
            caption: '음성 인식과 번역을 모두 Gemini로 처리합니다. Google AI Studio에서 '
                '무료로 발급한 Gemini 키 하나만 넣으면 됩니다.',
          ),
          const SizedBox(height: 16),
          Text(
            hasGeminiKey ? '키가 저장되어 있습니다.' : '키가 설정되지 않았습니다.',
            style: TextStyle(
              color: hasGeminiKey ? AppPalette.ink : AppPalette.inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _geminiKeyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Gemini 키 입력(비우고 저장하면 제거)',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _savingGemini ? null : _saveGeminiKey,
            child: Text(_savingGemini ? '저장 중…' : 'Gemini 키 저장'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ApiKeyGuideScreen(),
              ),
            ),
            icon: const Icon(Icons.help_outline),
            label: const Text('API 키 발급 방법'),
          ),
          const _SectionGap(),
          const _SectionHeader('언어'),
          const SizedBox(height: 12),
          Text('번역 대상 언어', style: _label(context)),
          DropdownButton<String>(
            value: current.targetLanguage,
            isExpanded: true,
            underline: const _DropdownUnderline(),
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
          Text('소스 언어(자동 감지 기본)', style: _label(context)),
          DropdownButton<String?>(
            value: current.languageHint,
            isExpanded: true,
            underline: const _DropdownUnderline(),
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
          const _SectionGap(),
          const _SectionHeader('표시 옵션'),
          const SizedBox(height: 4),
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
          const _SectionGap(),
          const _SectionHeader('자막 스타일'),
          const SizedBox(height: 16),
          _StylePreview(settings: current),
          const SizedBox(height: 20),
          Text('글자 크기 — ${current.subtitleFontSize.round()}', style: _label(context)),
          Slider(
            value: current.subtitleFontSize.clamp(14, 36),
            min: 14,
            max: 36,
            divisions: 22,
            label: current.subtitleFontSize.round().toString(),
            onChanged: settings.setSubtitleFontSize,
          ),
          const SizedBox(height: 8),
          Text('글자색', style: _label(context)),
          const SizedBox(height: 10),
          _ColorSwatchRow(
            colors: _textColors,
            selected: current.subtitleTextColor,
            onSelected: settings.setSubtitleTextColor,
          ),
          const SizedBox(height: 20),
          Text('배경색', style: _label(context)),
          const SizedBox(height: 10),
          _ColorSwatchRow(
            colors: _bgColors,
            selected: current.subtitleBgColor,
            onSelected: settings.setSubtitleBgColor,
          ),
          const SizedBox(height: 20),
          Text('배경 투명도 — ${(current.subtitleBgOpacity * 100).round()}%',
              style: _label(context)),
          Slider(
            value: current.subtitleBgOpacity.clamp(0, 1),
            divisions: 20,
            label: '${(current.subtitleBgOpacity * 100).round()}%',
            onChanged: settings.setSubtitleBgOpacity,
          ),
          const _SectionGap(),
          const _SectionHeader('저장공간'),
          const SizedBox(height: 12),
          Text(
            '캐시 사용량 — '
            '${_cacheBytes == null ? '계산 중…' : formatBytes(_cacheBytes!)}',
            style: _label(context),
          ),
          const SizedBox(height: 6),
          Text(
            '영상 선택 시 임시로 복사된 파일과 음성 인식용 임시 파일을 정리합니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _clearing ? null : _clearCache,
            icon: const Icon(Icons.delete_outline),
            label: Text(_clearing ? '비우는 중…' : '캐시 비우기'),
          ),
        ],
      ),
    );
  }
}

/// 섹션 라벨(소제목) 텍스트 스타일.
TextStyle? _label(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
          color: AppPalette.ink,
        );

/// 섹션 사이 간격 + 상단 hairline.
class _SectionGap extends StatelessWidget {
  const _SectionGap();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        SizedBox(height: 28),
        Divider(height: 1),
        SizedBox(height: 28),
      ],
    );
  }
}

/// 섹션 제목(+선택 캡션). 산세리프 미디엄, 색 강조 없이 여백으로 구분.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.caption});

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: textTheme.headlineSmall),
        if (caption != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(caption!, style: textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// 드롭다운 밑줄(에디토리얼 hairline).
class _DropdownUnderline extends StatelessWidget {
  const _DropdownUnderline();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: AppPalette.hairline);
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
