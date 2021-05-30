import 'dart:convert';

import "package:http/http.dart" as http;
import "package:http/retry.dart";

class _Client {
  final _client = RetryClient(http.Client());

  final host;
  final protocol;

  _Client({this.host = "localhost:8080", this.protocol = "http"});

  Future<Map<String, dynamic>> getSettings() =>
      _fetchJson("$protocol://$host/settings");

  Future<Map<String, dynamic>> getService(String name) =>
      _fetchJson("$protocol://$host/services/$name");

  Future<Map<String, dynamic>> getMessage(String name) =>
      _fetchJson("$protocol://$host/messages/$name");

  Future<Map<String, dynamic>> getComment(String name) =>
      _fetchJson("$protocol://$host/comments/$name");

  Future<Map<String, dynamic>> _fetchJson(String s) {
    var url = Uri.parse(s);
    return _client.get(url).then((resp) {
      if (resp.statusCode != 200) {
        return Future.error("got a ${resp.statusCode} calling $s");
      }
      try {
        return json.decode(resp.body);
      } catch (err) {
        return Future.error(err);
      }
    });
  }
}

final _instance = _Client();

_Client getInstance() => _instance;
