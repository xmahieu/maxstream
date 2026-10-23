import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const defaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

class NetError implements Exception {
  final String message;
  NetError(this.message);
  @override
  String toString() => message;
}

final _client = http.Client();

Future<List<int>> fetchBytes(String url, {Duration timeout = const Duration(seconds: 30), Map<String, String>? headers}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) throw NetError('invalid address');
  try {
    final resp = await _client.get(uri, headers: {'User-Agent': defaultUserAgent, ...?headers}).timeout(timeout);
    if (resp.statusCode >= 400) throw NetError('HTTP ${resp.statusCode}');
    List<int> body = resp.bodyBytes;
    if (body.length > 2 && body[0] == 0x1f && body[1] == 0x8b) {
      body = GZipCodec().decode(body);
    }
    return body;
  } on NetError {
    rethrow;
  } on SocketException catch (e) {
    throw NetError(e.osError?.message ?? e.message);
  } on HandshakeException {
    throw NetError('SSL error');
  } on http.ClientException catch (e) {
    throw NetError(e.message);
  } catch (e) {
    if (e.toString().contains('TimeoutException')) throw NetError('timeout');
    throw NetError(e.toString());
  }
}

String decodeText(List<int> bytes) {
  try {
    final text = utf8.decode(bytes);
    return text.startsWith('﻿') ? text.substring(1) : text;
  } on FormatException {
    return latin1.decode(bytes);
  }
}

Future<String> fetchText(String url, {Duration timeout = const Duration(seconds: 60)}) async =>
    decodeText(await fetchBytes(url, timeout: timeout));

Future<dynamic> fetchJson(String url, {Duration timeout = const Duration(seconds: 30)}) async {
  final text = await fetchText(url, timeout: timeout);
  if (text.trim().isEmpty) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    throw NetError('invalid answer from server');
  }
}
