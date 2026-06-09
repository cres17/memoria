const editorVisibleTabPrefsKey = 'editor.visibleTabs.v1';

List<T> normalizeEditorVisibleTabs<T>({
  required Iterable<String>? storedNames,
  required List<T> allTabs,
  required List<T> defaultTabs,
  required String Function(T tab) nameOf,
}) {
  List<T> normalizeDefaults() {
    final defaults = <T>[];
    for (final tab in defaultTabs) {
      if (allTabs.contains(tab) && !defaults.contains(tab)) {
        defaults.add(tab);
      }
      if (defaults.length == 4) return defaults;
    }
    for (final tab in allTabs) {
      if (!defaults.contains(tab)) {
        defaults.add(tab);
      }
      if (defaults.length == 4) return defaults;
    }
    return defaults;
  }

  final fallback = normalizeDefaults();
  if (storedNames == null) return fallback;

  final parsed = <T>[];
  for (final name in storedNames) {
    for (final tab in allTabs) {
      if (nameOf(tab) == name && !parsed.contains(tab)) {
        parsed.add(tab);
        break;
      }
    }
  }

  return parsed.length == 4 ? parsed : fallback;
}

List<String> visibleTabNames<T>(
  List<T> tabs,
  String Function(T tab) nameOf,
) {
  return tabs.take(4).map(nameOf).toList(growable: false);
}
