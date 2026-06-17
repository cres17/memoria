import 'app_locale.dart';

/// Lightweight string lookup used until the app moves to ARB localization.
class S {
  S._();

  static String get(String key) {
    final lang = localeNotifier.value.languageCode;
    return (lang == 'en' ? _en[key] : _ko[key]) ?? _ko[key] ?? key;
  }

  static const _ko = {
    'app.tagline': '나만의 사진 작업실',
    'home.headline': '사진의 분위기를\n오래 남길 이미지로.',
    'home.subtitle': '좋아하는 사진의 톤을 고르고, 기본 보정 도구로 차분하게 다듬어 보세요.',
    'home.cta': '사진 편집 시작',
    'home.location': 'Kyoto, Japan',
    'home.photo_title': 'Summer in\nArashiyama',
    'home.card_tones': '톤 라이브러리',
    'home.card_tones_body': '기본 필터, 커스텀 필터, 세밀한 보정 도구를 한 곳에서 관리합니다.',
    'home.card_ai': '필터 제작 스튜디오',
    'home.card_ai_body': '사진 한 장에서 나만의 LUT 필터를 자동 생성합니다. 원클릭으로 색감을 분석하고 저장합니다.',

    'filters.title': '나의 컬렉션',
    'filters.subtitle': '저장한 커스텀 필터와 기본 톤 라이브러리입니다.',
    'filters.loading': '필터를 불러오는 중입니다.',
    'filters.load_error': '필터를 불러오지 못했습니다.',
    'filters.retry': '다시 시도',
    'filters.new': '새 필터',

    'create.heading': '스타일 분석',
    'create.subheading': '선택한 사진의 색감, 팔레트, 분위기 태그를 분석해 65³ LUT 필터를 자동 생성합니다.',
    'create.analyzing': '분석 중',
    'create.select': '이미지 선택',
    'create.ready': '스타일 준비 완료',
    'create.palette': '팔레트',
    'create.detected': '감지된 스타일',
    'create.name_label': '필터 이름',
    'create.name_hint': '예: 여름 필름, 저녁 산책',
    'create.btn_image': '이미지',
    'create.btn_save': '필터 생성',
    'create.btn_cancel': '닫기',
    'create.done': '확인',
    'create.need_image': '스타일을 분석할 이미지를 먼저 선택해 주세요.',
    'create.need_name': '나중에 저장할 필터 이름을 입력해 주세요.',
    'create.deferred': '필터 생성 중 오류가 발생했습니다.',
    'create.error': '필터 생성 중 오류가 발생했습니다.',
    'create.success': '필터 생성 완료',
    'create.success_sub': '필터 목록에서 적용하거나 지금 바로 편집할 수 있어요.',
    'create.btn_edit_now': '이 필터로 사진 편집하기',
    'create.before': 'BEFORE',
    'create.after': 'AFTER',

    'settings.title': '설정',
    'settings.language': '언어',
    'settings.lang_ko': '한국어',
    'settings.lang_en': 'English',
    'settings.storage': '저장소',
    'settings.filter_location': '필터 저장 위치',
    'settings.filter_loc_sub': '앱 내부 저장소',
    'settings.clear_cache': '캐시 지우기',
    'settings.clear_cache_title': '캐시 지우기',
    'settings.clear_cache_body': '임시 파일을 모두 삭제합니다.',
    'settings.clear_cache_cancel': '취소',
    'settings.clear_cache_confirm': '삭제',
    'settings.clear_cache_done': '캐시가 삭제되었습니다.',
    'settings.clear_cache_fail': '삭제 실패',
    'settings.quality': '품질',
    'settings.export_quality': '내보내기 품질',
    'settings.export_quality_sub': 'JPEG 95%',
    'settings.export_format': '내보내기 파일 포맷',
    'settings.export_format_sub': '저장 포맷 선택 (JPEG, PNG, WebP, RAW)',
    'settings.about': '앱 정보',
    'settings.licenses': '오픈소스 라이선스',
    'settings.version': '버전',
    'settings.dev_hint': '개발자 모드까지 {n}번 더 탭하세요',

    'settings.ai': 'AI 모델',
    'settings.ai_color': '색감 이전 모델',
    'settings.ai_color_sub': '필터 자동 생성 엔진 (~18 MB)',
    'settings.ai_download': '다운로드',
    'settings.ai_downloading': '다운로드 중',
    'settings.ai_ready': '준비 완료',
    'settings.ai_error': '오류',

    'editor.invalid_image': '이미지를 열 수 없습니다.',
    'editor.no_image_selected': '사진을 선택하세요',
    'editor.select_photo': '사진 선택',
    'editor.go_back': '돌아가기',
    'editor.saved_to_gallery': '사진 앱에 저장되었습니다.',
    'editor.save_failed': '저장 실패',
    'editor.exporting': '내보내는 중...',
    'editor.cancel_export': '취소',

    'permission.photos_denied': '사진 접근 권한이 필요합니다.',
    'permission.camera_denied': '카메라 접근 권한이 필요합니다.',

    'perspective.temporary_note': '수평 및 수직 원근 왜곡을 조절합니다.',
    'perspective.horizontal': '수평',
    'perspective.vertical': '수직',
    'perspective.decrease': '감소',
    'perspective.increase': '증가',
    'perspective.reset': '전체 초기화',

    // Details
    'details.structure': '구조',
    'details.clarity': '선명도',
    'details.sharpen': '샤프닝',

    // HSL
    'hsl.hue': '색조',
    'hsl.saturation': '채도',
    'hsl.luminance': '밝기',
    'hsl.red': '빨강',
    'hsl.orange': '주황',
    'hsl.yellow': '노랑',
    'hsl.green': '초록',
    'hsl.cyan': '청록',
    'hsl.blue': '파랑',
    'hsl.purple': '보라',
    'hsl.magenta': '자홍',

    // Glow
    'glow.strength': '글로우 강도',
    'glow.saturation': '채도',
    'glow.warmth': '따뜻함',

    // Vignette
    'vignette.strength': '비네팅 강도',

    // Grain
    'grain.strength': '그레인 강도',
    'grain.size': '입자 크기',
    'grain.seed': '패턴 시드',
    'grain.randomize': '임의 생성',

    // Split
    'split.shadows': '어두운 영역',
    'split.highlights': '밝은 영역',
    'split.balance': '균형',
    'split.saturation': '채도',

    // Noise
    'noise.luminance': '밝기 노이즈 감소',
    'noise.colour': '색상 노이즈 감소',
    'noise.detail': '세부 정보 유지',

    // HDR
    'hdr.strength': 'HDR 강도',
    'hdr.saturation': '채도',

    // Light Leak
    'light_leak.strength': '광학유출 강도',
    'light_leak.angle': '각도',
    'light_leak.warmth': '따뜻함',

    // Halation
    'halation.strength': '할레이션 강도',
    'halation.threshold': '임계값',
    'halation.warmth': '따뜻함',
  };

  static const _en = {
    'app.tagline': 'Your Photo Workspace',
    'home.headline': 'Shape a photo mood\ninto something lasting.',
    'home.subtitle': 'Choose a tone you like, then refine it with calm, focused editing tools.',
    'home.cta': 'Start Editing',
    'home.location': 'Kyoto, Japan',
    'home.photo_title': 'Summer in\nArashiyama',
    'home.card_tones': 'Tone Library',
    'home.card_tones_body': 'Manage built-in filters, custom filters, and detailed adjustments in one place.',
    'home.card_ai': 'Filter Studio',
    'home.card_ai_body': 'Auto-generate a custom LUT filter from a single photo. Analyze and save your color signature in one tap.',
 
    'filters.title': 'My Collection',
    'filters.subtitle': 'Your saved custom filters and built-in tone library.',
    'filters.loading': 'Loading filters...',
    'filters.load_error': 'Failed to load filters.',
    'filters.retry': 'Retry',
    'filters.new': 'New Filter',

    'create.heading': 'Style Analysis',
    'create.subheading': 'Analyze the palette, colors, and style tags from a photo and auto-generate a 65³ LUT filter.',
    'create.analyzing': 'Analyzing',
    'create.select': 'Select Image',
    'create.ready': 'Style Ready',
    'create.palette': 'Palette',
    'create.detected': 'Detected',
    'create.name_label': 'Filter name',
    'create.name_hint': 'Summer Film, Evening Walk...',
    'create.btn_image': 'Image',
    'create.btn_save': 'Create Filter',
    'create.btn_cancel': 'Close',
    'create.done': 'Done',
    'create.need_image': 'Select an image to analyze first.',
    'create.need_name': 'Enter a filter name for later saving.',
    'create.deferred': 'An error occurred while creating the filter.',
    'create.error': 'An error occurred while creating the filter.',
    'create.success': 'Filter created',
    'create.success_sub': 'Apply it from your filter list, or edit a photo with it now.',
    'create.btn_edit_now': 'Edit a photo with this filter',
    'create.before': 'BEFORE',
    'create.after': 'AFTER',

    'settings.title': 'Settings',
    'settings.language': 'Language',
    'settings.lang_ko': '한국어',
    'settings.lang_en': 'English',
    'settings.storage': 'Storage',
    'settings.filter_location': 'Filter Storage',
    'settings.filter_loc_sub': 'App internal storage',
    'settings.clear_cache': 'Clear Cache',
    'settings.clear_cache_title': 'Clear Cache',
    'settings.clear_cache_body': 'Delete all temporary files.',
    'settings.clear_cache_cancel': 'Cancel',
    'settings.clear_cache_confirm': 'Delete',
    'settings.clear_cache_done': 'Cache cleared.',
    'settings.clear_cache_fail': 'Failed to delete',
    'settings.quality': 'Quality',
    'settings.export_quality': 'Export Quality',
    'settings.export_quality_sub': 'JPEG 95%',
    'settings.export_format': 'Export File Format',
    'settings.export_format_sub': 'Select format (JPEG, PNG, WebP, RAW)',
    'settings.about': 'About',
    'settings.licenses': 'Open Source Licenses',
    'settings.version': 'Version',
    'settings.dev_hint': '{n} more taps to developer mode',

    'settings.ai': 'AI Models',
    'settings.ai_color': 'Color Transfer Model',
    'settings.ai_color_sub': 'Auto filter generation engine (~18 MB)',
    'settings.ai_download': 'Download',
    'settings.ai_downloading': 'Downloading',
    'settings.ai_ready': 'Ready',
    'settings.ai_error': 'Error',

    'editor.invalid_image': 'Unable to open image.',
    'editor.no_image_selected': 'Select a photo',
    'editor.select_photo': 'Select Photo',
    'editor.go_back': 'Go Back',
    'editor.saved_to_gallery': 'Saved to Photos.',
    'editor.save_failed': 'Save failed',
    'editor.exporting': 'Exporting...',
    'editor.cancel_export': 'Cancel',

    'permission.photos_denied': 'Photo access permission is required.',
    'permission.camera_denied': 'Camera access permission is required.',

    'perspective.temporary_note': 'Adjust horizontal and vertical perspective.',
    'perspective.horizontal': 'Horizontal',
    'perspective.vertical': 'Vertical',
    'perspective.decrease': 'Decrease',
    'perspective.increase': 'Increase',
    'perspective.reset': 'Reset',

    // Details
    'details.structure': 'Structure',
    'details.clarity': 'Clarity',
    'details.sharpen': 'Sharpening',

    // HSL
    'hsl.hue': 'Hue',
    'hsl.saturation': 'Saturation',
    'hsl.luminance': 'Luminance',
    'hsl.red': 'Red',
    'hsl.orange': 'Orange',
    'hsl.yellow': 'Yellow',
    'hsl.green': 'Green',
    'hsl.cyan': 'Cyan',
    'hsl.blue': 'Blue',
    'hsl.purple': 'Purple',
    'hsl.magenta': 'Magenta',

    // Glow
    'glow.strength': 'Glow Strength',
    'glow.saturation': 'Saturation',
    'glow.warmth': 'Warmth',

    // Vignette
    'vignette.strength': 'Vignette Strength',

    // Grain
    'grain.strength': 'Grain Strength',
    'grain.size': 'Grain Size',
    'grain.seed': 'Pattern Seed',
    'grain.randomize': 'Randomize',

    // Split
    'split.shadows': 'Shadows',
    'split.highlights': 'Highlights',
    'split.balance': 'Balance',
    'split.saturation': 'Saturation',

    // Noise
    'noise.luminance': 'Luminance Noise Reduction',
    'noise.colour': 'Color Noise Reduction',
    'noise.detail': 'Preserve Detail',

    // HDR
    'hdr.strength': 'HDR Strength',
    'hdr.saturation': 'Saturation',

    // Light Leak
    'light_leak.strength': 'Light Leak Strength',
    'light_leak.angle': 'Angle',
    'light_leak.warmth': 'Warmth',

    // Halation
    'halation.strength': 'Halation Strength',
    'halation.threshold': 'Threshold',
    'halation.warmth': 'Warmth',
  };
}
