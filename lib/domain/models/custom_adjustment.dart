import 'dart:convert';
import 'adjust_params.dart';

class CustomAdjustment {
  final String id;
  final String name;
  final AdjustParams params;
  final DateTime createdAt;

  const CustomAdjustment({
    required this.id,
    required this.name,
    required this.params,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'params': params.toJson(),
        'created_at': createdAt.toIso8601String(),
      };

  factory CustomAdjustment.fromJson(Map<String, dynamic> json) =>
      CustomAdjustment(
        id: json['id'] as String,
        name: json['name'] as String,
        params: AdjustParams.fromJson(json['params'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  String toJsonString() => jsonEncode(toJson());
}
