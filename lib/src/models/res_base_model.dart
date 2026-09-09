import 'package:json_annotation/json_annotation.dart';

part 'res_base_model.g.dart';

@JsonSerializable()
class ResBaseModel {
  String? error;
  String? message;

  ResBaseModel({this.error, this.message});

  factory ResBaseModel.fromJson(Map<String, dynamic> json) =>
      _$ResBaseModelFromJson(json);

  Map<String, dynamic> toJson() => _$ResBaseModelToJson(this);
}
