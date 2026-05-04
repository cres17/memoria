import 'package:flutter/widgets.dart';
import 'app_locale.dart';

/// Simple string lookup — no external package required.
/// Add keys as needed; fall back to Korean.
class S {
  S._();

  static String get(String key) {
    final lang = localeNotifier.value.languageCode;
    return (_en[key] != null && lang == 'en') ? _en[key]! : _ko[key] ?? key;
  }

  // ── Home ───────────────────────────────────────────────
  static const _ko = {
    'app.tagline':       '나만의 사진 공간',
    'home.headline':     '소중한 순간을\n필터로 담다.',
    'home.subtitle':     '사진 한 장의 분위기를 나만의 필터로 만들고,\n오래 간직할 이미지로 다듬어보세요.',
    'home.cta':          '시작하기',
    'home.location':     '교토, 일본',
    'home.photo_title':  '아라시야마의\n여름',
    'home.card_tones':   '시그니처 톤',
    'home.card_tones_body': '따뜻한 필름 질감, 빈티지 커브, 로컬 보정을 한 화면에서 다듬습니다.',
    'home.card_ai':      'AI 필터 스튜디오',
    'home.card_ai_body': '좋아하는 사진의 색감에서 커스텀 LUT 필터를 생성합니다.',
    // Filters
    'filters.title':     '나의 컬렉션',
    'filters.subtitle':  '나만의 커스텀 필터와 기본 톤 라이브러리입니다.',
    'filters.loading':   '필터를 불러오는 중입니다.',
    'filters.new':       '새 필터',
    // Create filter
    'create.heading':    '스타일 분석',
    'create.subheading': '색상, 태그, 감성 정보를 추출합니다.',
    'create.analyzing':  '분석 중',
    'create.select':     '이미지 선택',
    'create.ready':      '스타일 준비 완료',
    'create.palette':    '팔레트',
    'create.detected':   '감지된 스타일',
    'create.name_label': '필터 이름',
    'create.name_hint':  '페이드 세피아, 여름 필름...',
    'create.btn_image':  '이미지',
    'create.btn_save':   '필터 저장',
    'create.btn_cancel': '취소',
    'create.done':       '확인',
    // Settings
    'settings.title':    '설정',
    'settings.language': '언어',
    'settings.lang_ko':  '한국어',
    'settings.lang_en':  'English',
    'settings.storage':  '저장소',
    'settings.filter_location': '필터 저장 위치',
    'settings.filter_loc_sub':  '앱 내부 저장소',
    'settings.clear_cache': '캐시 지우기',
    'settings.quality':  '화질',
    'settings.export_quality': '내보내기 품질',
    'settings.about':    '앱 정보',
    'settings.licenses': '오픈소스 라이선스',
    'settings.version':  '버전',
  };

  static const _en = {
    'app.tagline':       'Your Digital Sanctuary',
    'home.headline':     "Curate your life's\nbest moments.",
    'home.subtitle':     'Turn the mood of a photo into your own filter,\nand refine it into an image worth keeping.',
    'home.cta':          'Start Creating',
    'home.location':     'Kyoto, Japan',
    'home.photo_title':  'Summer in\nArashiyama',
    'home.card_tones':   'Signature Tones',
    'home.card_tones_body': 'Warm film texture, vintage curves, and local adjustments — all in one view.',
    'home.card_ai':      'AI Filter Studio',
    'home.card_ai_body': 'Generate a custom LUT filter from the color palette of any photo.',
    // Filters
    'filters.title':     'My Collection',
    'filters.subtitle':  'Your custom filters and built-in tone library.',
    'filters.loading':   'Loading filters...',
    'filters.new':       'New Filter',
    // Create filter
    'create.heading':    'Uncovering Details',
    'create.subheading': 'Extracting colors, tags, and sentiment.',
    'create.analyzing':  'Analyzing',
    'create.select':     'SELECT IMAGE',
    'create.ready':      'STYLE READY',
    'create.palette':    'Palette',
    'create.detected':   'Detected',
    'create.name_label': 'Filter name',
    'create.name_hint':  'Faded Sepia, Summer Grain...',
    'create.btn_image':  'Image',
    'create.btn_save':   'Save Filter',
    'create.btn_cancel': 'Cancel',
    'create.done':       'Done',
    // Settings
    'settings.title':    'Settings',
    'settings.language': 'Language',
    'settings.lang_ko':  '한국어',
    'settings.lang_en':  'English',
    'settings.storage':  'Storage',
    'settings.filter_location': 'Filter Storage',
    'settings.filter_loc_sub':  'App internal storage',
    'settings.clear_cache': 'Clear Cache',
    'settings.quality':  'Quality',
    'settings.export_quality': 'Export Quality',
    'settings.about':    'About',
    'settings.licenses': 'Open Source Licenses',
    'settings.version':  'Version',
  };
}
