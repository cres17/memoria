import 'dart:convert';
import 'adjust_params.dart';
import 'editor_look.dart';

class CustomAdjustment {
  final String id;
  final String name;
  final AdjustParams params;
  final DateTime createdAt;

  /// 필터·효과·인물 보정까지 포함한 저장본. 이전 버전에서 저장한 항목은 null이며
  /// 이때는 [params]만 적용한다.
  final EditorLook? look;

  const CustomAdjustment({
    required this.id,
    required this.name,
    required this.params,
    required this.createdAt,
    this.look,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'params': params.toJson(),
        'created_at': createdAt.toIso8601String(),
        if (look != null) 'look': look!.toJson(),
      };

  factory CustomAdjustment.fromJson(Map<String, dynamic> json) =>
      CustomAdjustment(
        id: json['id'] as String,
        name: json['name'] as String,
        params: AdjustParams.fromJson(json['params'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['created_at'] as String),
        look: json['look'] is Map<String, dynamic>
            ? EditorLook.fromJson(json['look'] as Map<String, dynamic>)
            : null,
      );

  String toJsonString() => jsonEncode(toJson());
}
