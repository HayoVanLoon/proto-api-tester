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
  List<Widget> methods = [];
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
    return Column(
      children: [
        ListTile(
          title: Text(_name),
          onTap: () => _toggleOpen(),
        ),
        Column(
          children: methods,
        )
      ],
    );
  }

  _toggleOpen() {
    setState(() {
      _opened = !_opened;
    });
    if (methods.isEmpty) {
      _getDescriptor().then((desc) {
        setState(() {
          for (ResolvedServiceMethod m in desc.methods) {
            methods.add(MethodWidget(m));
          }
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
      fieldWidgets.add(FieldWidget(i, 1, f, getter, setter));
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

class FieldWidget extends StatelessWidget {
  final int _idx;
  final int _level;
  final Function(Value) _setter;
  final ResolvedField _field;
  final Value Function() _getter;
  late final String _name;

  FieldWidget(this._idx, this._level, this._field, this._getter, this._setter) {
    _name = _field.name;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(0, indent, 0, 0),
          alignment: Alignment.centerLeft,
          child: _withCommentPopup(context, Text(_name), _field.comment),
        ),
        _buildInput(),
      ],
    );
  }

  Widget _buildInput() {
    var value = _getter();
    if (!_field.repeated) {
      var getter = () => _getter();
      var setter = (val) {
        var v = _getter();
        v.set(val);
        _setter(v);
      };
      return _buildSimple(_field.type, _field.repeated, getter, setter);
    } else {
      var ws = <Widget>[];
      for (var i = 0; i < value.length(); i += 1) {
        var getter = () => _getter().at(i);
        var setter = (val) {
          var v = _getter();
          v.setAt(i, val);
          _setter(v);
        };
        ws.add(Container(
          color: _idx + i % 2 == 0 ? colourEven : colourOdd,
          child: Row(
            children: [
              Expanded(
                  child: _buildSimple(
                      _field.type, _field.repeated, getter, setter)),
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
      return Column(
        children: [
          ...ws,
          TextButton(
            onPressed: () {
              var value = _getter();
              value.add(Value.empty(_field.type, false));
              _setter(value);
            },
            child: Row(children: [Icon(Icons.add), Text(_name)]),
          ),
        ],
      );
    }
  }

  Widget _buildSimple(String fieldType, bool repeated, Value Function() getter,
      Function(Value) setter) {
    switch (fieldType) {
      case prototypeInt32:
      case prototypeInt64:
        var text = getter().isEmpty() ? "" : getter().intValue().toString();
        return _textInput(_level, text, fieldType, repeated, setter);
      case prototypeString:
        var text = getter().isEmpty() ? "" : getter().stringValue()!;
        return _textInput(_level, text, fieldType, repeated, setter);
      case prototypeMessage:
        return _mapInput(_level, _idx, _field.nested!.fields, getter, setter);
      default:
        return Text("$_name: ${_field.type}");
    }
  }

  static Widget _textInput(int level, String text, String fieldType,
      bool repeated, Function(Value) setter) {
    var isString = fieldType == prototypeString;
    return _withPadding(
      level,
      TextFormField(
        controller: inputSetter(text),
        keyboardType: isString
            ? TextInputType.text
            : TextInputType.numberWithOptions(decimal: false),
        inputFormatters:
            isString ? [] : [FilteringTextInputFormatter.digitsOnly],
        onChanged: (val) {
          var v = val.isEmpty
              ? Value.empty(fieldType, false)
              : isString
                  ? Value.string(val)
                  : Value.int(int.parse(val));
          setter(v);
        },
      ),
    );
  }

  static Widget _mapInput(int level, int idx, List<ResolvedField> fields,
      Value Function() getter, Function(Value) setter) {
    var nested = <Widget>[];
    for (ResolvedField f in fields) {
      var getFn = () => getter().getOrEmpty(f.name, f.type, f.repeated);
      var setFn = (val) {
        var value = getter();
        value.put(f.name, val);
        setter(value);
      };
      nested.add(
        _withPadding(level, FieldWidget(idx, level + 1, f, getFn, setFn)),
      );
    }
    return Column(
      children: [
        ...nested,
      ],
    );
  }

  static Widget _withPadding(int level, Widget w) {
    return Padding(
      padding: EdgeInsets.fromLTRB(level * indent, 0, 0, 0),
      child: w,
    );
  }
}

TextEditingController inputSetter(String s) {
  var c = TextEditingController();
  c.value = TextEditingValue(
    text: s,
    selection: TextSelection.collapsed(offset: s.length),
  );
  return c;
}
