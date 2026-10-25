import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';

/// 저장된 편집 기록·초안 JSON은 앱을 업데이트해도 읽혀야 한다.
///
/// `test/fixtures/schema/effect_state_keys.json` 은 지금까지 저장 형식에 쓰인 모든 키 목록이다.
///  - 키를 지우거나 이름을 바꾸면 이 테스트가 실패한다 → 마이그레이션을 만들고 fixture를 갱신해야 한다.
///  - 키를 추가하는 것은 허용되지만, fixture에 추가해 이후 삭제를 막는다.
///    (`UPDATE_SCHEMA_FIXTURES=1 flutter test test/schema_compat_test.dart` 로 갱신)
void main() {
  final fixture = File('test/fixtures/schema/effect_state_keys.json');

  Set<String> currentKeys() =>
      const EditorEffectState().toJson().keys.toSet();

  test('저장 키 목록 fixture를 갱신한다 (UPDATE_SCHEMA_FIXTURES=1 일 때만)', () {
    if (Platform.environment['UPDATE_SCHEMA_FIXTURES'] != '1') return;
    final known = fixture.existsSync()
        ? (jsonDecode(fixture.readAsStringSync()) as List).cast<String>().toSet()
        : <String>{};
    final merged = (known..addAll(currentKeys())).toList()..sort();
    fixture.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(merged)}\n');
  });

  test('지금까지 저장 형식에 쓰인 키가 하나도 사라지거나 이름이 바뀌지 않았다', () {
    final known =
        (jsonDecode(fixture.readAsStringSync()) as List).cast<String>().toSet();
    final missing = known.difference(currentKeys());
    expect(missing, isEmpty,
        reason: '저장된 데이터를 읽는 키가 사라졌다: $missing. 마이그레이션을 추가하세요.');
  });

  test('새 키가 fixture에 등록되어 있다 (등록해야 이후 삭제가 막힌다)', () {
    final known =
        (jsonDecode(fixture.readAsStringSync()) as List).cast<String>().toSet();
    final unregistered = currentKeys().difference(known);
    expect(unregistered, isEmpty,
        reason: 'fixture에 없는 새 저장 키: $unregistered. '
            'UPDATE_SCHEMA_FIXTURES=1 로 갱신하세요.');
  });

  test('모르는 키가 섞인 미래 버전 기록도 예외 없이 읽는다', () {
    final op = EditOperation.fromJson({
      'id': 'future',
      'tool': 'someToolAddedLater',
      'v': 99,
      'at': '2030-01-01T00:00:00.000Z',
      'params': const AdjustParams(exposure: 0.3).toJson(),
      'effects': {
        ...const EditorEffectState().toJson(),
        'fieldFromTheFuture': {'a': 1},
      },
      'extraTopLevel': true,
    });
    expect(op.schemaVersion, 99);
    expect(op.tool, EditToolType.globalAdjust, reason: '모르는 도구는 기본 도구로 대체');
    expect(op.params!.exposure, 0.3);
    expect(op.effectState, isNotNull);
  });

  test('효과 키가 하나도 없는 예전 기록은 모든 값이 기본값이다', () {
    final state = EditorEffectState.fromJson(const {});
    final defaults = const EditorEffectState();
    expect(jsonEncode(state.toJson()), jsonEncode(defaults.toJson()));
  });
}
