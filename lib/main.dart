import 'dart:convert';

import 'package:flutter/cupertino.dart';
import "package:flutter/material.dart";
import 'package:flutter/services.dart';

import "client.dart" as client;
import "models.dart";
import 'style.dart';
import 'value.dart';

void main() => runApp(ApiTester());

class ApiTester extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'API Tester',
      home: Scaffold(
        appBar: AppBar(title: Text("API Tester")),
        body: Container(
          child: ServicesList(),
        ),
      ),
    );
  }
}

class ServicesList extends StatefulWidget {
  @override
  _ServicesListState createState() {
    return _ServicesListState();
  }
}

var _client = client.getInstance();

class _ServicesListState extends State<ServicesList> {
  final _services = <String>[];
  String _gatewayUrl = "";

  _ServicesListState() {
    _getSettings();
  }

  _getSettings() async {
    var data = await _client.getSettings();
    var settings = AppSettings.fromJson(data);
    setState(() {
      _services.addAll(settings.services);
      _services.sort();
      _gatewayUrl = settings.gatewayUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_services.length == 0) {
      return Center(child: Text("... fetching list ... "));
    }

    var widgets = <Widget>[];
    for (var i = 0; i < _services.length; i += 1) {
      if (i > 0) {
        widgets.add(Divider());
      }
      widgets.add(_buildService(_services[i]));
    }
    return Container(
      width: MediaQuery.of(context).size.width,
      child: ListView(
        padding: EdgeInsets.all(16.0),
        children: widgets,
      ),
    );
  }

  Widget _buildService(String service) {
    return ServiceWidget(service);
  }
}

class ServiceWidget extends StatefulWidget {
  final String _name;

  ServiceWidget(this._name);

  @override
  State<StatefulWidget> createState() {
    return _ServiceWidgetState(_name);
  }
}

class _ServiceWidgetState extends State<ServiceWidget> {
  bool _opened = false;
  final _name;
  List<ResolvedServiceMethod> _methods = [];
  late Future<ResolvedService> Function() _getDescriptor;

  _ServiceWidgetState(this._name) {
    this._getDescriptor = () => getService(this._name);
  }

  @override
  Widget build(BuildContext context) {
    if (!_opened) {
      return ListTile(
        title: Text(_name),
        onTap: () => _toggleOpen(),
      );
    }
    var ws = <Widget>[];
    var i = 0;
    for (ResolvedServiceMethod m in _methods) {
      if (i > 0) {
        ws.add(Divider());
      }
      ws.add(MethodWidget(m));
      i += 1;
    }
    return Column(
      children: [
        ListTile(
          title: Text(_name),
          onTap: () => _toggleOpen(),
        ),
        Column(
          children: ws,
        )
      ],
    );
  }

  _toggleOpen() {
    setState(() {
      _opened = !_opened;
    });
    if (_methods.isEmpty) {
      _getDescriptor().then((desc) {
        setState(() {
          _methods.addAll(desc.methods);
        });
      });
    }
  }
}

class MethodWidget extends StatelessWidget {
  final ResolvedServiceMethod _details;

  MethodWidget(this._details);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _withCommentPopup(context, Text(_details.name), _details.comment),
        Container(
          width: MediaQuery.of(context).size.width,
          child: RequestForm(_details.inputType.fullName),
        ),
        Text(_details.outputType.name),
      ],
    );
  }
}

class RequestForm extends StatefulWidget {
  final String _inputType;

  const RequestForm(this._inputType);

  @override
  State<StatefulWidget> createState() {
    return _RequestFormState(_inputType);
  }
}

const indent = 4.0;

class _RequestFormState extends State<RequestForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final String _inputType;
  ResolvedMessage? message;
  Value _value = Value.empty(prototypeMessage, false);

  _RequestFormState(this._inputType) {
    getMessage(this._inputType)
        .then((desc) => setState(() => {this.message = desc}));
  }

  @override
  Widget build(BuildContext context) {
    if (message == null) {
      return Text("Loading ...");
    }
    List<Widget> fieldWidgets = [];
    for (var i = 0; i < message!.fields.length; i += 1) {
      var f = message!.fields[i];
      var getter = () => _value.getOrEmpty(f.name, f.type, f.repeated);
      var setter = (val) {
        setState(() {
          _value.put(f.name, val);
        });
      };
      fieldWidgets.add(FieldWidget.create(i, 1, f, getter, setter));
    }
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _withCommentPopup(
            context,
            Align(alignment: Alignment.centerLeft, child: Text(message!.name)),
            message!.comment,
          ),
          ...fieldWidgets,
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: ElevatedButton(
                onPressed: () => _handleSubmit(),
                child: Text("Submit"),
              ),
            ),
          ),
          Text(() {
            var clean = _value.protoJson();
            return clean == null ? "" : jsonEncode(clean);
          }()),
        ],
      ),
    );
  }

  void _handleSubmit() {
    if (_formKey.currentState!.validate()) {
      var clean = _value.protoJson();
      print("submitted: $clean");
      return;
    }
    print("input error");
  }
}

Widget _withCommentPopup(BuildContext context, Widget child, String comment) {
  if (comment == "") {
    return child;
  }
  var fn = () {
    showDialog(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        children: [
          Text(comment),
        ],
      ),
      barrierDismissible: true,
    );
  };
  return Row(children: [
    child,
    IconButton(
      onPressed: fn,
      icon: Icon(Icons.info, size: 18, color: colourInfo),
    ),
  ]);
}

abstract class FieldWidget extends StatelessWidget {
  final int idx;
  final int level;
  final Function(Value) _setter;
  final ResolvedField _field;
  final Value Function() _getter;
  late final String name;

  FieldWidget(this.idx, this.level, this._field, this._getter, this._setter) {
    name = _field.name;
  }

  factory FieldWidget.create(int idx, int level, ResolvedField f,
      Value Function() getter, Function(Value) setter) {
    switch (f.type) {
      case prototypeInt32:
      case prototypeInt64:
        return IntFieldWidget(idx, level + 1, f, getter, setter);
      case prototypeString:
        return StringFieldWidget(idx, level + 1, f, getter, setter);
      case prototypeMessage:
        return MessageFieldWidget(idx, level + 1, f, getter, setter);
      default:
        return TodoFieldWidget(idx, level + 1, f, getter, setter);
    }
  }

  @override
  Widget build(BuildContext context) {
    var ws = <Widget>[];

    // Add display name
    ws.add(Container(
      padding: EdgeInsets.fromLTRB(0, indent, 0, 0),
      alignment: Alignment.centerLeft,
      child: _withCommentPopup(context, Text(name), _field.comment),
    ));

    // Add value(s)
    if (!_field.repeated) {
      var getter = () => _getter();
      var setter = (val) {
        var v = _getter();
        v.set(val);
        _setter(v);
      };
      ws.add(_buildSimple(getter, setter));
    } else {
      var value = _getter();
      for (var i = 0; i < value.length(); i += 1) {
        var getter = () => _getter().at(i);
        var setter = (val) {
          var v = _getter();
          v.setAt(i, val);
          _setter(v);
        };
        // Pair value and delete-item button
        ws.add(Container(
          color: idx + i % 2 == 0 ? colourEven : colourOdd,
          child: Row(
            children: [
              Expanded(child: _buildSimple(getter, setter)),
              TextButton(
                onPressed: () {
                  var value = _getter();
                  value.removeAt(i);
                  _setter(value);
                },
                child: Icon(Icons.delete),
              ),
            ],
          ),
        ));
      }

      // Add add-item button
      ws.add(TextButton(
        onPressed: () {
          var value = _getter();
          value.add(Value.empty(_field.type, false));
          _setter(value);
        },
        child: Row(children: [Icon(Icons.add), Text(name)]),
      ));
    }

    return Column(
      children: ws,
    );
  }

  Widget _buildSimple(Value Function() getter, Function(Value) setter);

  Widget _withPadding(Widget w) {
    return Padding(
      padding: EdgeInsets.fromLTRB(level * indent, 0, 0, 0),
      child: w,
    );
  }
}

TextEditingValue inputSetter(String s) {
  return TextEditingValue(
    text: s,
    selection: TextSelection.collapsed(offset: s.length),
  );
}

class IntFieldWidget extends FieldWidget {
  final TextEditingController _controller = TextEditingController();

  IntFieldWidget(int idx, int level, ResolvedField field,
      Value Function() getter, Function(Value) setter)
      : super(idx, level, field, getter, setter) {
    switch (_field.type) {
      case prototypeInt32:
      case prototypeInt64:
        break;
      default:
        throw "$name is not a int32 or int64 field";
    }
  }

  Widget _buildSimple(Value Function() getter, Function(Value) setter) {
    var text = getter().isEmpty() ? "" : getter().intValue().toString();
    _controller.value = inputSetter(text);
    return _withPadding(TextFormField(
      controller: _controller,
      keyboardType: TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (val) {
        print(name + ": " + val);
        if (val.isEmpty) {
          setter(Value.empty(_field.type, false));
          return;
        }
        var i = int.parse(val);
        var v = _field.type == prototypeInt32 ? Value.int32(i) : Value.int64(i);
        setter(v);
      },
    ));
  }
}

class StringFieldWidget extends FieldWidget {
  final TextEditingController _controller = TextEditingController();

  StringFieldWidget(int idx, int level, ResolvedField field,
      Value Function() getter, Function(Value) setter)
      : super(idx, level, field, getter, setter) {
    if (_field.type != prototypeString) {
      throw "$name is not a string field";
    }
  }

  Widget _buildSimple(Value Function() getter, Function(Value) setter) {
    var text = getter().isEmpty() ? "" : getter().stringValue()!;
    _controller.value = inputSetter(text);
    return _withPadding(TextFormField(
      controller: _controller,
      onChanged: (val) {
        var v = val.isEmpty
            ? Value.empty(prototypeString, false)
            : Value.string(val);
        setter(v);
      },
    ));
  }
}

class MessageFieldWidget extends FieldWidget {
  MessageFieldWidget(int idx, int level, ResolvedField field,
      Value Function() getter, Function(Value) setter)
      : super(idx, level, field, getter, setter) {
    if (_field.type != prototypeMessage) {
      throw "$name is not a message field";
    }
  }

  Widget _buildSimple(Value Function() getter, Function(Value) setter) {
    var nested = <Widget>[];
    for (ResolvedField f in _field.nested!.fields) {
      var getFn = () => getter().getOrEmpty(f.name, f.type, f.repeated);
      var setFn = (val) {
        var value = getter();
        value.put(f.name, val);
        setter(value);
      };
      Widget w = FieldWidget.create(idx, level + 1, f, getFn, setFn);
      nested.add(_withPadding(w));
    }
    return Column(
      children: [
        ...nested,
      ],
    );
  }
}

class TodoFieldWidget extends FieldWidget {
  TodoFieldWidget(int idx, int level, ResolvedField field,
      Value Function() getter, Function(Value) setter)
      : super(idx, level, field, getter, setter);

  Widget _buildSimple(Value Function() getter, Function(Value) setter) {
    return Text("$name ${_field.type} (TODO)");
  }
}
