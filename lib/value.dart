const prototypeEnum = "TYPE_ENUM";
const prototypeInt32 = "TYPE_INT32";
const prototypeInt64 = "TYPE_INT64";
const prototypeMessage = "TYPE_MESSAGE";
const prototypeString = "TYPE_STRING";

class Value {
  String _type;
  final bool _repeated;

  List<Value> _listValue = [];
  int? _intValue;
  String? _stringValue;
  Map<String, Value>? _nested;

  Value.empty(this._type, this._repeated);

  Value.int32(int i)
      : _intValue = i,
        _type = prototypeInt32,
        _repeated = false;

  Value.int64(int i)
      : _intValue = i,
        _type = prototypeInt64,
        _repeated = false;

  Value.string(String s)
      : _stringValue = s,
        _type = prototypeString,
        _repeated = false;

  Value.nested(Map<String, Value> m)
      : _nested = m,
        _type = prototypeMessage,
        _repeated = false;

  bool isEmpty() =>
      _intValue == null &&
      _stringValue == null &&
      _nested == null &&
      _listValue.isEmpty;

  int length() => _listValue.length;

  @override
  String toString() {
    var xs = <String>[];
    if (_intValue != null) {
      xs.add("int:${_intValue!}");
    }
    if (_stringValue != null) {
      xs.add("string:${_stringValue!}");
    }
    if (_nested != null) {
      var ys = <String>[];
      for (MapEntry<String, Value> v in _nested!.entries) {
        ys.add("${v.key}: ${v.value}");
      }
      xs.add("map:{${ys.join(" ")}}");
    }
    if (_listValue.isNotEmpty) {
      var ys = _listValue.map((v) => v.toString());
      xs.add("[${ys.join(" ")}]");
    }
    return "(${xs.join(" ")})";
  }

  int? intValue() {
    if ((_type != prototypeInt32 && _type != prototypeInt64) || _repeated) {
      throw "not a simple int";
    }
    return _intValue;
  }

  String? stringValue() {
    if (_type != prototypeString || _repeated) {
      throw "not a simple string";
    }
    return _stringValue;
  }

  Map<String, Value>? mapValue() {
    if (_type != prototypeMessage || _repeated) {
      throw "not a simple string";
    }
    return _nested;
  }

  Value at(int i) {
    if (_listValue.isEmpty) {
      throw "index out of bounds: $i (${_listValue.length})";
    }
    return _listValue[i];
  }

  void setInt(int? i) {
    if (_type != prototypeInt32 && _type != prototypeInt64) {
      throw "invalid type added for ($_type)";
    }
    if (_repeated) {
      throw "not a list value";
    }
    _intValue = i;
  }

  void setString(String? s) {
    if (_type != prototypeString || _repeated) {
      throw "invalid type added for ($_type)";
    }
    if (_repeated) {
      throw "not a list value";
    }
    _stringValue = s;
  }

  void setNested(Map<String, Value>? v) {
    if (_type != prototypeMessage || _repeated) {
      throw "invalid type added for ($_type)";
    }
    if (_repeated) {
      throw "not a list value";
    }
    _nested = v;
  }

  void set(Value val) {
    if (val._type != this._type) {
      throw "invalid type: ${val._type} ($_type)";
    }
    assert(val.length() <= 1);
    switch (_type) {
      case prototypeInt32:
        setInt(val.intValue());
        break;
      case prototypeInt64:
        setInt(val.intValue());
        break;
      case prototypeMessage:
        setNested(val.mapValue());
        break;
      case prototypeString:
        setString(val.stringValue());
        break;
      default:
        throw "unsupported value type $_type";
    }
  }

  void add(Value val) {
    if (!_repeated) {
      throw "this value is not a list";
    }
    if (val._type != this._type) {
      throw "invalid type added: ${val._type} ($_type)";
    }
    if (val._repeated) {
      throw "may not add repeated value";
    }
    _listValue.add(val);
  }

  void removeAt(int i) {
    if (!_repeated) {
      throw "this value is not a list";
    }
    _listValue.removeAt(i);
  }

  void setAt(int i, Value val) {
    if (!_repeated) {
      throw "this value is not a list";
    }
    if (val._type != this._type) {
      throw "invalid type added: ${val._type} ($_type)";
    }
    if (val._repeated) {
      throw "may not set with a repeated value";
    }
    _listValue[i] = val;
  }

  Value? get(String name) {
    if (_type != prototypeMessage) {
      throw "not a nested";
    }
    return _nested == null ? null : _nested![name];
  }

  Value getOrEmpty(String name, String type, bool repeated) {
    if (_type != prototypeMessage) {
      throw "not a nested";
    }
    var v = get(name);
    return v == null ? Value.empty(type, repeated) : v;
  }

  void put(String name, Value v) {
    if (_type != prototypeMessage) {
      throw "not a nested";
    }
    if (_nested == null) {
      _nested = {};
    }
    _nested![name] = v;
  }

  dynamic protoJson() {
    if (_repeated) {
      var xs = [];
      for (Value v in _listValue) {
        var clean = v.protoJson();
        if (clean != null) {
          xs.add(clean);
        }
      }
      return xs.isEmpty ? null : xs;
    }
    switch (_type) {
      case prototypeInt64:
        return _intValue;
      case prototypeMessage:
        if (_nested == null) {
          return null;
        }
        var xs = {};
        for (MapEntry<String, Value> e in _nested!.entries) {
          var clean = e.value.protoJson();
          if (clean != null) {
            xs[e.key] = clean;
          }
        }
        return xs.isEmpty ? null : xs;
      case prototypeString:
        return _stringValue;
    }
  }
}
