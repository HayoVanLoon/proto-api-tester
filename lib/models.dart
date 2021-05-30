import 'package:json_annotation/json_annotation.dart';

import 'client.dart' as client;

part "models.g.dart";

const _prototypeEnum = "TYPE_ENUM";
const _prototypeInt32 = "TYPE_INT32";
const _prototypeInt64 = "TYPE_INT64";
const _prototypeMessage = "TYPE_MESSAGE";
const _prototypeString = "TYPE_STRING";

@JsonSerializable()
class AppSettings {
  @JsonKey(defaultValue: [])
  final List<String> services;

  @JsonKey(defaultValue: "")
  final String gatewayUrl;

  AppSettings(this.services, this.gatewayUrl);

  factory AppSettings.fromJson(Map<String, dynamic> data) =>
      _$AppSettingsFromJson(data);

  Map<String, dynamic> toJson() => _$AppSettingsToJson(this);
}

@JsonSerializable()
class ServiceDescriptorProto {
  final String name;
  @JsonKey(defaultValue: [])
  final List<ServiceMethod> method;

  ServiceDescriptorProto(this.name, this.method);

  factory ServiceDescriptorProto.fromJson(Map<String, dynamic> data) =>
      _$ServiceDescriptorProtoFromJson(data);

  Map<String, dynamic> toJson() => _$ServiceDescriptorProtoToJson(this);
}

@JsonSerializable()
class ServiceMethod {
  final String name;
  final String inputType;
  final String outputType;

  ServiceMethod(this.name, this.inputType, this.outputType);

  factory ServiceMethod.fromJson(Map<String, dynamic> data) =>
      _$ServiceMethodFromJson(data);

  Map<String, dynamic> toJson() => _$ServiceMethodToJson(this);
}

@JsonSerializable()
class MessageDescriptorProto {
  final String name;
  @JsonKey(defaultValue: [])
  final List<MessageField> field;
  @JsonKey(defaultValue: [])
  final List<MessageDescriptorProto> nestedType;
  @JsonKey(defaultValue: [])
  final List<OneofDescriptorProto> oneofDecl;

  // @JsonKey(defaultValue: [])
  // final List<EnumProto> enumType;

  MessageDescriptorProto(
      this.name, this.field, this.nestedType, this.oneofDecl);

  factory MessageDescriptorProto.fromJson(Map<String, dynamic> data) =>
      _$MessageDescriptorProtoFromJson(data);

  Map<String, dynamic> toJson() => _$MessageDescriptorProtoToJson(this);
}

@JsonSerializable()
class MessageField {
  final String name;
  final String type;
  final String? typeName;
  final String label;
  final int? oneofIndex;

  MessageField(
      this.name, this.type, this.typeName, this.label, this.oneofIndex);

  factory MessageField.fromJson(Map<String, dynamic> data) =>
      _$MessageFieldFromJson(data);

  Map<String, dynamic> toJson() => _$MessageFieldToJson(this);
}

@JsonSerializable()
class OneofDescriptorProto {
  final String name;

  OneofDescriptorProto(this.name);

  factory OneofDescriptorProto.fromJson(Map<String, dynamic> data) =>
      _$OneofDescriptorProtoFromJson(data);

  Map<String, dynamic> toJson() => _$OneofDescriptorProtoToJson(this);
}

@JsonSerializable()
class Comment {
  final String text;

  Comment(this.text);

  factory Comment.fromJson(Map<String, dynamic> data) =>
      _$CommentFromJson(data);

  Map<String, dynamic> toJson() => _$CommentToJson(this);
}

class ResolvedService {
  final ServiceDescriptorProto desc;
  final String name;
  final List<ResolvedServiceMethod> methods;
  final String comment;

  ResolvedService(this.desc, this.name, this.methods, this.comment);
}

class ResolvedServiceMethod {
  final ServiceMethod desc;
  late final String name;
  final ResolvedMessage inputType;
  final ResolvedMessage outputType;
  final String comment;

  ResolvedServiceMethod(
      this.desc, this.inputType, this.outputType, this.comment) {
    name = desc.name;
  }
}

class ResolvedMessage {
  final String fullName;
  final String name;
  final String comment;
  final List<ResolvedField> fields;

  ResolvedMessage(this.fullName, this.name, this.fields, this.comment);
}

class ResolvedField {
  final String name;
  final String type;
  final ResolvedMessage? nested;
  final bool repeated;
  final String comment;

  ResolvedField(this.name, this.type, this.nested, this.repeated, this.comment);
}

const protoLabelOptional = "LABEL_OPTIONAL";
const protoLabelRepeated = "LABEL_REPEATED";

final _serviceCatalog = <String, ResolvedService>{};
final _messageCatalog = <String, ResolvedMessage>{};
final _commentsCatalog = <String, Comment>{};

var _client = client.getInstance();

Future<ResolvedService> getService(String name) {
  ResolvedService? svc = _serviceCatalog[name];
  if (svc != null) {
    return Future.value(svc);
  }
  return _client.getService(name).then((data) {
    var desc = ServiceDescriptorProto.fromJson((data));
    return resolveService(desc, name).then((svc) {
      _serviceCatalog[name] = svc;
      return svc;
    });
  });
}

Future<ResolvedMessage> getMessage(String name) {
  var cleanName = stripLeft(name, ".");
  ResolvedMessage? m = _messageCatalog[name];
  if (m != null) {
    return Future.value(m);
  }
  return _client.getMessage(cleanName).then((data) {
    var desc = MessageDescriptorProto.fromJson(data);
    return resolveMessage(desc, cleanName).then((m) {
      _messageCatalog[cleanName] = m;
      return m;
    });
  });
}

Future<Comment> getComment(String name) {
  Comment? c = _commentsCatalog[name];
  if (c != null) {
    return Future.value(c);
  }
  return _client.getComment(name).then((data) {
    var c = Comment.fromJson(data);
    _commentsCatalog[name] = c;
    return c;
  }).onError((error, stackTrace) => Comment(""));
}

String stripLeft(String s, String del) {
  for (var i = 0; i < s.length; i += 1) {
    if (s[i] != del) {
      return s.substring(i);
    }
  }
  return "";
}

Future<ResolvedService> resolveService(
    ServiceDescriptorProto desc, String fullName) {
  fullName = stripLeft(fullName, ".");
  Future<Comment> serviceCommentFt = getComment(fullName);
  List<Future<ResolvedServiceMethod>> methodFts = [];
  for (ServiceMethod m in desc.method) {
    var fullMethod = fullName + "." + m.name;
    var inputFt = getMessage(m.inputType);
    var outputFt = getMessage(m.outputType);
    var commentFt = getComment(fullMethod);
    var methodFt = Future.wait([inputFt, outputFt, commentFt]).then((xs) {
      var inputType = (xs[0] as ResolvedMessage);
      var outputType = (xs[1] as ResolvedMessage);
      var comment = (xs[2] as Comment);
      return ResolvedServiceMethod(m, inputType, outputType, comment.text);
    });
    methodFts.add(methodFt);
  }
  return Future.wait([Future.wait(methodFts), serviceCommentFt]).then((xs) {
    var methods = (xs[0] as List).cast<ResolvedServiceMethod>();
    var comment = (xs[1] as Comment);
    return ResolvedService(desc, fullName, methods, comment.text);
  });
}

Future<ResolvedMessage> resolveMessage(
    MessageDescriptorProto desc, String fullName) {
  fullName = stripLeft(fullName, ".");
  Future<Comment> commentFt = getComment(fullName);
  List<Future<ResolvedField>> fieldFts = [];
  for (MessageField field in desc.field) {
    var fullField = fullName + "." + field.name;
    if (field.type != _prototypeMessage) {
      var repeated = field.label == protoLabelRepeated;
      var ft = getComment(fullField).then(
          (c) => ResolvedField(field.name, field.type, null, repeated, c.text));
      fieldFts.add(ft);
      continue;
    }
    if (field.typeName == null) {
      throw "type is TYPE_MESSAGE but no field.typeName for ${field.name}";
    }
    var ft1 = getMessage(field.typeName!);
    var ft2 = getComment(fullField);
    var ft = Future.wait([ft1, ft2]).then((mc) {
      var m = (mc[0] as ResolvedMessage);
      var comment = (mc[1] as Comment);
      var repeated = field.label == protoLabelRepeated;
      return ResolvedField(field.name, field.type, m, repeated, comment.text);
    });
    fieldFts.add(ft);
  }

  return Future.wait([Future.wait(fieldFts), commentFt]).then((cfs) {
    var fields = (cfs[0] as List).cast<ResolvedField>();
    var comment = (cfs[1] as Comment);
    return ResolvedMessage(fullName, desc.name, fields, comment.text);
  });
}
