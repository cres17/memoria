import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/features/editor/editor_tab_preferences.dart';

void main() {
  const allTabs = [
    'filters',
    'adjust',
    'details',
    'curves',
    'tools',
    'portrait',
  ];
  const defaults = ['filters', 'adjust', 'tools', 'portrait'];

  List<String> normalize(Iterable<String>? names) {
    return normalizeEditorVisibleTabs<String>(
      storedNames: names,
      allTabs: allTabs,
      defaultTabs: defaults,
      nameOf: (tab) => tab,
    );
  }

  test('valid stored tabs are preserved in order', () {
    expect(
      normalize(['curves', 'details', 'filters', 'tools']),
      ['curves', 'details', 'filters', 'tools'],
    );
  });

  test('missing, duplicate, and future tab names recover to defaults', () {
    expect(normalize(null), defaults);
    expect(normalize(['filters', 'filters', 'tools', 'portrait']), defaults);
    expect(normalize(['filters', 'unknown', 'tools', 'portrait']), defaults);
    expect(normalize(['filters', 'adjust', 'tools']), defaults);
    expect(normalize(['filters', 'adjust', 'tools', 'portrait', 'curves']),
        defaults);
  });

  test('saved names are capped to four entries', () {
    expect(
      visibleTabNames(
          ['filters', 'adjust', 'tools', 'portrait', 'curves'], (tab) => tab),
      ['filters', 'adjust', 'tools', 'portrait'],
    );
  });
}
