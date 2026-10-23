import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Persistent state: playlists, settings, favourites, resume points, history,
/// plus a file cache for the (large) catalogues.
class Store {
  static late SharedPreferences _p;
  static late Directory _cacheDir;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    final base = await getApplicationSupportDirectory();
    _cacheDir = Directory('${base.path}${Platform.pathSeparator}cache');
    if (!_cacheDir.existsSync()) _cacheDir.createSync(recursive: true);
  }

  // ------------------------------------------------------------ helpers
  static dynamic _json(String key, dynamic def) {
    final raw = _p.getString(key);
    if (raw == null) return def;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return def;
    }
  }

  static Future<void> _setJson(String key, dynamic value) => _p.setString(key, jsonEncode(value));

  // ------------------------------------------------------------ playlists
  static List<Playlist> playlists() => [
        for (final j in (_json('playlists', []) as List)) Playlist.fromJson(Map<String, dynamic>.from(j as Map)),
      ];

  static Future<void> savePlaylists(List<Playlist> list) => _setJson('playlists', [for (final p in list) p.toJson()]);

  static String get activeId => _p.getString('active') ?? '';
  static set activeId(String id) => _p.setString('active', id);

  static Playlist? activePlaylist() {
    final all = playlists();
    if (all.isEmpty) return null;
    return all.firstWhere((p) => p.id == activeId, orElse: () => all.first);
  }

  // ------------------------------------------------------------ settings
  static int getInt(String key, int def) => _p.getInt('s_$key') ?? def;
  static Future<void> setInt(String key, int v) => _p.setInt('s_$key', v);
  static bool getBool(String key, bool def) => _p.getBool('s_$key') ?? def;
  static Future<void> setBool(String key, bool v) => _p.setBool('s_$key', v);
  static String getString(String key, String def) => _p.getString('s_$key') ?? def;
  static Future<void> setString(String key, String v) => _p.setString('s_$key', v);

  // ------------------------------------------------------------ favourites
  static Map<String, dynamic> _favs(String pid) => Map<String, dynamic>.from(_json('fav_$pid', {}) as Map);

  static bool isFavourite(String pid, String key) => _favs(pid).containsKey(key);

  static Future<void> toggleFavourite(String pid, Item item) async {
    final favs = _favs(pid);
    if (favs.containsKey(item.key)) {
      favs.remove(item.key);
    } else {
      favs[item.key] = item.toJson();
    }
    await _setJson('fav_$pid', favs);
  }

  static List<Item> favourites(String pid, Kind kind) => [
        for (final v in _favs(pid).values)
          if (toInt((v as Map)['k']) == kind.index) Item.fromJson(Map<String, dynamic>.from(v)),
      ];

  // ------------------------------------------------------------ resume / history
  static Map<String, dynamic> _resume(String pid) => Map<String, dynamic>.from(_json('resume_$pid', {}) as Map);

  static Map<String, dynamic>? resumeOf(String pid, String key) {
    final r = _resume(pid)[key];
    return r == null ? null : Map<String, dynamic>.from(r as Map);
  }

  /// Saves the position; past 92 % (or < 2 min left) the video counts as watched.
  static Future<void> saveResume(String pid, String key, int pos, int total, Map<String, dynamic>? item) async {
    if (total <= 0) return;
    final all = _resume(pid);
    final watched = pos >= total * 0.92 || total - pos < 120;
    all[key] = {'pos': watched ? 0 : pos, 'total': total, 'watched': watched, 'ts': DateTime.now().millisecondsSinceEpoch};
    if (all.length > 800) {
      final keys = all.keys.toList()
        ..sort((a, b) => toInt((all[a] as Map)['ts']).compareTo(toInt((all[b] as Map)['ts'])));
      for (final k in keys.take(all.length - 800)) {
        all.remove(k);
      }
    }
    await _setJson('resume_$pid', all);
    if (item != null) await _addHistory(pid, key, item);
  }

  static Future<void> _addHistory(String pid, String key, Map<String, dynamic> item) async {
    final list = [for (final e in (_json('hist_$pid', []) as List)) Map<String, dynamic>.from(e as Map)];
    list.removeWhere((e) => e['key'] == key);
    list.insert(0, {'key': key, 'item': item});
    await _setJson('hist_$pid', list.take(getInt('history_size', 60)).toList());
  }

  /// Unfinished movies / episodes, most recent first.
  static List<(Map<String, dynamic>, Map<String, dynamic>)> continueWatching(String pid) {
    final resume = _resume(pid);
    final out = <(Map<String, dynamic>, Map<String, dynamic>)>[];
    for (final e in (_json('hist_$pid', []) as List)) {
      final entry = Map<String, dynamic>.from(e as Map);
      final r = resume[entry['key']];
      if (r is Map && toInt(r['pos']) > 0 && r['watched'] != true) {
        out.add((entry, Map<String, dynamic>.from(r)));
      }
    }
    return out;
  }

  static Future<void> removeHistory(String pid, String key) async {
    final list = [for (final e in (_json('hist_$pid', []) as List)) Map<String, dynamic>.from(e as Map)];
    list.removeWhere((e) => e['key'] == key);
    await _setJson('hist_$pid', list);
  }

  // recently watched channels
  static List<Item> recentChannels(String pid) => [
        for (final j in (_json('recent_$pid', []) as List)) Item.fromJson(Map<String, dynamic>.from(j as Map)),
      ];

  static Future<void> addRecentChannel(String pid, Item ch) async {
    final list = recentChannels(pid)..removeWhere((c) => c.id == ch.id);
    list.insert(0, ch);
    await _setJson('recent_$pid', [for (final c in list.take(30)) c.toJson()]);
  }

  // ------------------------------------------------------------ file cache
  static File _cacheFile(String name) => File('${_cacheDir.path}${Platform.pathSeparator}$name.json');

  static Future<dynamic> readCache(String name, Duration ttl) async {
    final f = _cacheFile(name);
    if (!f.existsSync()) return null;
    if (DateTime.now().difference(f.lastModifiedSync()) > ttl) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeCache(String name, dynamic data) async {
    try {
      await _cacheFile(name).writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Future<void> clearCache([String prefix = '']) async {
    for (final f in _cacheDir.listSync()) {
      if (f is File && f.uri.pathSegments.last.startsWith(prefix)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }
}
