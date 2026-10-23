import 'dart:convert';

import 'epg.dart';
import 'm3u.dart';
import 'models.dart';
import 'net.dart';
import 'store.dart';

String normalizeServer(String url) {
  url = url.trim();
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) url = 'http://$url';
  url = url.replaceFirst(RegExp(r'/(player_api|get|xmltv|panel_api)\.php.*$', caseSensitive: false), '');
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// http://host:port/get.php?username=u&password=p&type=m3u_plus -> (server, user, pass)
(String, String, String)? parseXtreamLink(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.path.toLowerCase().endsWith('/get.php')) return null;
  final u = uri.queryParameters['username'];
  final p = uri.queryParameters['password'];
  if (u == null || p == null) return null;
  final path = uri.path.substring(0, uri.path.length - '/get.php'.length);
  return ('${uri.scheme.isEmpty ? 'http' : uri.scheme}://${uri.authority}$path', u, p);
}

String _b64(dynamic v) {
  final s = toStr(v);
  if (s.isEmpty) return '';
  try {
    return utf8.decode(base64.decode(s), allowMalformed: true);
  } catch (_) {
    return s;
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

String _stamp(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}:${_two(t.hour)}-${_two(t.minute)}';

abstract class Provider {
  final Playlist pl;
  Provider(this.pl);

  Duration get ttl => Duration(hours: Store.getInt('cache_hours', 12));

  final Map<Kind, List<Category>> _cats = {};
  final Map<Kind, List<Item>> _items = {};

  Future<void> check();
  Future<List<Category>> categories(Kind kind);
  Future<List<Item>> allItems(Kind kind);
  Future<MovieDetail> movieDetail(Item movie);
  Future<SeriesDetail> seriesDetail(Item series);
  String streamUrl(Item item);
  String episodeUrl(Episode ep);
  Future<List<Programme>> shortEpg(Item channel);
  Future<List<Programme>> channelProgrammes(Item channel);
  String? catchupUrl(Item channel, Programme p);
  Future<Map<String, String>?> accountInfo() async => null;

  Future<List<Item>> items(Kind kind, {String? cat}) async {
    final all = await allItems(kind);
    if (cat == null) return all;
    return all.where((i) => i.cat == cat).toList();
  }

  Future<List<Item>> search(Kind kind, String query) async {
    final q = fold(query);
    if (q.isEmpty) return [];
    final words = q.split(' ').where((w) => w.isNotEmpty).toList();
    final all = await allItems(kind);
    return all.where((i) {
      final n = fold(i.name);
      return words.every(n.contains);
    }).take(500).toList();
  }

  Future<void> refresh() async {
    _cats.clear();
    _items.clear();
    await Store.clearCache('${pl.id}_');
  }
}

String fold(String s) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().runes) {
    final c = String.fromCharCode(ch);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

Provider providerFor(Playlist pl) => pl.isXtream ? XtreamProvider(pl) : M3UProvider(pl);

// ====================================================================== Xtream
class XtreamProvider extends Provider {
  final String server;
  XtreamProvider(super.pl) : server = normalizeServer(pl.server);

  String get _u => Uri.encodeComponent(pl.username);
  String get _p => Uri.encodeComponent(pl.password);

  Future<dynamic> api([String? action, Map<String, String> params = const {}]) {
    final q = {'username': pl.username, 'password': pl.password, if (action != null) 'action': action, ...params};
    return fetchJson('$server/player_api.php?${Uri(queryParameters: q).query}');
  }

  Future<dynamic> _cached(String key, Future<dynamic> Function() load) async {
    final name = '${pl.id}_$key';
    final cached = await Store.readCache(name, ttl);
    if (cached != null) return cached;
    final data = await load();
    if (data != null) await Store.writeCache(name, data);
    return data;
  }

  @override
  Future<void> check() async {
    final info = await api();
    final user = info is Map ? info['user_info'] : null;
    if (user is! Map || toStr(user['auth']) == '0') throw NetError('authentication failed');
  }

  @override
  Future<Map<String, String>?> accountInfo() async {
    final info = await api();
    if (info is! Map) return null;
    final user = Map<String, dynamic>.from((info['user_info'] ?? {}) as Map);
    String date(dynamic v) {
      final t = toInt(v);
      if (t <= 0) return '';
      final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
      return '${_two(d.day)}/${_two(d.month)}/${d.year}';
    }

    return {
      'username': toStr(user['username']),
      'status': toStr(user['status']),
      'exp': date(user['exp_date']),
      'connections': '${toStr(user['active_cons'])} / ${toStr(user['max_connections'])}',
      'created': date(user['created_at']),
      'server': server,
    };
  }

  static const _actions = {
    Kind.live: ['get_live_categories', 'get_live_streams'],
    Kind.movie: ['get_vod_categories', 'get_vod_streams'],
    Kind.series: ['get_series_categories', 'get_series'],
  };

  @override
  Future<List<Category>> categories(Kind kind) async {
    if (_cats[kind] != null) return _cats[kind]!;
    final data = await _cached('cats_${kind.name}', () => api(_actions[kind]![0]));
    final list = <Category>[
      if (data is List)
        for (final c in data)
          if (c is Map) Category(toStr(c['category_id']), toStr(c['category_name'])),
    ];
    return _cats[kind] = list;
  }

  @override
  Future<List<Item>> allItems(Kind kind) async {
    if (_items[kind] != null) return _items[kind]!;
    final name = '${pl.id}_items_${kind.name}';
    final cached = await Store.readCache(name, ttl);
    List<Item> list;
    if (cached is List) {
      list = [for (final j in cached) Item.fromJson(Map<String, dynamic>.from(j as Map))];
    } else {
      var data = await api(_actions[kind]![1]);
      if (data is Map) data = data.values.toList();
      list = [
        if (data is List)
          for (final i in data)
            if (i is Map) _norm(kind, Map<String, dynamic>.from(i)),
      ];
      await Store.writeCache(name, [for (final i in list) i.toJson()]);
    }
    return _items[kind] = list;
  }

  Item _norm(Kind kind, Map<String, dynamic> i) {
    switch (kind) {
      case Kind.live:
        return Item(
          kind: kind,
          id: toStr(i['stream_id']),
          name: toStr(i['name']),
          icon: toStr(i['stream_icon']),
          cat: toStr(i['category_id']),
          epgId: toStr(i['epg_channel_id']),
          num: toInt(i['num']),
          catchup: toInt(i['tv_archive']) == 1,
          catchupDays: toInt(i['tv_archive_duration']),
          added: toInt(i['added']),
        );
      case Kind.movie:
        return Item(
          kind: kind,
          id: toStr(i['stream_id']),
          name: toStr(i['name']),
          icon: toStr(i['stream_icon']),
          cat: toStr(i['category_id']),
          rating: toDouble(i['rating']),
          added: toInt(i['added']),
          year: yearOf(i['year'] ?? i['name']),
          ext: toStr(i['container_extension']).isEmpty ? 'mp4' : toStr(i['container_extension']),
          plot: toStr(i['plot']),
        );
      case Kind.series:
        return Item(
          kind: kind,
          id: toStr(i['series_id']),
          name: toStr(i['name']),
          icon: toStr(i['cover']),
          cat: toStr(i['category_id']),
          rating: toDouble(i['rating']),
          added: toInt(i['last_modified']),
          year: yearOf(i['releaseDate'] ?? i['release_date']),
          plot: toStr(i['plot']),
          genre: toStr(i['genre']),
          backdrop: toStr(i['backdrop_path']),
        );
    }
  }

  @override
  Future<MovieDetail> movieDetail(Item movie) async {
    final raw = await _cached('vod_${movie.id}', () => api('get_vod_info', {'vod_id': movie.id}));
    final info = raw is Map && raw['info'] is Map ? Map<String, dynamic>.from(raw['info'] as Map) : <String, dynamic>{};
    return MovieDetail(
      name: toStr(info['name']).isEmpty ? movie.name : toStr(info['name']),
      plot: toStr(info['plot']).isEmpty ? toStr(info['description']) : toStr(info['plot']),
      cast: toStr(info['cast']).isEmpty ? toStr(info['actors']) : toStr(info['cast']),
      director: toStr(info['director']),
      genre: toStr(info['genre']),
      year: yearOf(info['releasedate'] ?? info['release_date']),
      duration: toInt(info['duration_secs']),
      rating: toDouble(info['rating']),
      icon: toStr(info['movie_image']).isEmpty ? movie.icon : toStr(info['movie_image']),
      backdrop: toStr(info['backdrop_path']),
      trailer: toStr(info['youtube_trailer']),
    );
  }

  @override
  Future<SeriesDetail> seriesDetail(Item series) async {
    final raw = await _cached('series_${series.id}', () => api('get_series_info', {'series_id': series.id}));
    final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final info = m['info'] is Map ? Map<String, dynamic>.from(m['info'] as Map) : <String, dynamic>{};
    final show = toStr(info['name']).isEmpty ? series.name : toStr(info['name']);
    dynamic groups = m['episodes'];
    if (groups is List) {
      final list = groups;
      groups = <String, dynamic>{for (var i = 0; i < list.length; i++) '${i + 1}': list[i]};
    }
    final seasons = <int, List<Episode>>{};
    if (groups is Map) {
      groups.forEach((key, eps) {
        if (eps is! List) return;
        for (final e in eps) {
          if (e is! Map) continue;
          final ei = e['info'] is Map ? e['info'] as Map : const {};
          final s = toInt(e['season'], toInt(key));
          seasons.putIfAbsent(s, () => []).add(Episode(
                id: toStr(e['id']),
                title: toStr(e['title']),
                season: s,
                episode: toInt(e['episode_num']),
                icon: toStr(ei['movie_image']),
                plot: toStr(ei['plot']),
                duration: toInt(ei['duration_secs']),
                ext: toStr(e['container_extension']).isEmpty ? 'mp4' : toStr(e['container_extension']),
                show: show,
                seriesId: series.id,
              ));
        }
      });
    }
    for (final l in seasons.values) {
      l.sort((a, b) => a.episode.compareTo(b.episode));
    }
    final sorted = Map.fromEntries(seasons.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    return SeriesDetail(
      name: show,
      plot: toStr(info['plot']).isEmpty ? series.plot : toStr(info['plot']),
      icon: toStr(info['cover']).isEmpty ? series.icon : toStr(info['cover']),
      backdrop: toStr(info['backdrop_path']),
      genre: toStr(info['genre']),
      cast: toStr(info['cast']),
      director: toStr(info['director']),
      rating: toDouble(info['rating']),
      year: yearOf(info['releaseDate']),
      seasons: sorted,
    );
  }

  @override
  String streamUrl(Item item) {
    switch (item.kind) {
      case Kind.live:
        final ext = Store.getInt('live_format', 0) == 1 ? 'm3u8' : 'ts';
        return '$server/live/$_u/$_p/${item.id}.$ext';
      case Kind.movie:
        return '$server/movie/$_u/$_p/${item.id}.${item.ext.isEmpty ? 'mp4' : item.ext}';
      case Kind.series:
        return '';
    }
  }

  @override
  String episodeUrl(Episode ep) => '$server/series/$_u/$_p/${ep.id}.${ep.ext.isEmpty ? 'mp4' : ep.ext}';

  @override
  Future<List<Programme>> shortEpg(Item channel) async {
    final raw = await api('get_short_epg', {'stream_id': channel.id, 'limit': '4'});
    final list = raw is Map ? raw['epg_listings'] : null;
    return [
      if (list is List)
        for (final p in list)
          if (p is Map)
            Programme(toInt(p['start_timestamp']), toInt(p['stop_timestamp']), _b64(p['title']), desc: _b64(p['description'])),
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  @override
  Future<List<Programme>> channelProgrammes(Item channel) async {
    final raw = await api('get_simple_data_table', {'stream_id': channel.id});
    final list = raw is Map ? raw['epg_listings'] : null;
    final out = <Programme>[
      if (list is List)
        for (final p in list)
          if (p is Map)
            Programme(
              toInt(p['start_timestamp']),
              toInt(p['stop_timestamp']),
              _b64(p['title']),
              desc: _b64(p['description']),
              archive: toInt(p['has_archive']) == 1,
              serverStart: toStr(p['start']),
            ),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  @override
  String? catchupUrl(Item channel, Programme p) {
    final minutes = ((p.stop - p.start) / 60).ceil().clamp(1, 100000);
    String stamp;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})').firstMatch(p.serverStart);
    if (m != null) {
      stamp = '${m[1]}-${m[2]}-${m[3]}:${m[4]}-${m[5]}';
    } else {
      stamp = _stamp(DateTime.fromMillisecondsSinceEpoch(p.start * 1000));
    }
    return '$server/timeshift/$_u/$_p/$minutes/$stamp/${channel.id}.ts';
  }
}

// ====================================================================== M3U
class M3UProvider extends Provider {
  M3UProvider(super.pl);

  M3UData? _db;
  Map<String, List<Programme>>? _epg;
  Future<void>? _epgLoading;

  Future<M3UData> db({bool force = false}) async {
    if (_db != null && !force) return _db!;
    final name = '${pl.id}_m3u';
    if (!force) {
      final cached = await Store.readCache(name, ttl);
      if (cached is Map) return _db = M3UData.fromJson(Map<String, dynamic>.from(cached));
    }
    final text = await fetchText(pl.m3uUrl, timeout: const Duration(seconds: 120));
    final data = buildM3U(text);
    if (data.items.values.every((l) => l.isEmpty)) throw NetError('empty playlist');
    await Store.writeCache(name, data.toJson());
    return _db = data;
  }

  @override
  Future<void> check() async => db(force: true);

  @override
  Future<List<Category>> categories(Kind kind) async => (await db()).cats[kind] ?? [];

  @override
  Future<List<Item>> allItems(Kind kind) async => (await db()).items[kind] ?? [];

  @override
  Future<MovieDetail> movieDetail(Item movie) async => MovieDetail(name: movie.name, year: movie.year, icon: movie.icon);

  @override
  Future<SeriesDetail> seriesDetail(Item series) async {
    final eps = (await db()).episodes[series.id] ?? [];
    final seasons = <int, List<Episode>>{};
    for (final e in eps) {
      seasons.putIfAbsent(e.season, () => []).add(e);
    }
    for (final l in seasons.values) {
      l.sort((a, b) => a.episode.compareTo(b.episode));
    }
    return SeriesDetail(
      name: series.name,
      icon: series.icon,
      year: series.year,
      seasons: Map.fromEntries(seasons.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
    );
  }

  @override
  String streamUrl(Item item) => item.url;

  @override
  String episodeUrl(Episode ep) => ep.url;

  List<String> epgUrls() {
    final urls = <String>[];
    if (pl.epgUrl.isNotEmpty) urls.add(pl.epgUrl);
    final h = _db?.header ?? {};
    for (final k in ['url-tvg', 'x-tvg-url', 'tvg-url']) {
      for (final u in (h[k] ?? '').split(',')) {
        if (u.trim().isNotEmpty && !urls.contains(u.trim())) urls.add(u.trim());
      }
    }
    if (urls.isEmpty) {
      final x = parseXtreamLink(pl.m3uUrl);
      if (x != null) {
        urls.add('${x.$1}/xmltv.php?${Uri(queryParameters: {'username': x.$2, 'password': x.$3}).query}');
      }
    }
    return urls;
  }

  Future<void> _loadEpg() async {
    await db();
    final out = <String, List<Programme>>{};
    for (final url in epgUrls()) {
      try {
        final cached = await Store.readCache('${pl.id}_epg', const Duration(hours: 12));
        if (cached is Map) {
          out.addAll(epgFromJson(Map<String, dynamic>.from(cached)));
          break;
        }
        final text = await fetchText(url, timeout: const Duration(seconds: 180));
        final parsed = await parseXmltvInBackground(text);
        out.addAll(parsed);
        await Store.writeCache('${pl.id}_epg', epgToJson(parsed));
        break;
      } catch (_) {}
    }
    _epg = out;
  }

  Future<List<Programme>> _programmes(Item channel) async {
    if (_epg == null) {
      _epgLoading ??= _loadEpg();
      await _epgLoading;
    }
    final epg = _epg ?? {};
    return epg[channel.epgId] ?? epg[channel.epgId.toLowerCase()] ?? epg[fold(channel.name)] ?? [];
  }

  @override
  Future<List<Programme>> shortEpg(Item channel) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return (await _programmes(channel)).where((p) => p.stop > now).take(4).toList();
  }

  @override
  Future<List<Programme>> channelProgrammes(Item channel) async {
    final progs = await _programmes(channel);
    if (!channel.catchup) return progs;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final limit = now - (channel.catchupDays > 0 ? channel.catchupDays : 7) * 86400;
    return [
      for (final p in progs)
        Programme(p.start, p.stop, p.title, desc: p.desc, archive: p.start >= limit && p.stop <= now),
    ];
  }

  @override
  String? catchupUrl(Item channel, Programme p) =>
      buildCatchupUrl(channel.url, channel.catchupMode, channel.catchupSource, p.start, p.stop);
}

// ====================================================================== catch-up templates
String _fillTemplate(String template, int start, int stop) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final values = <String, int>{
    'utc': start,
    'start': start,
    'utcend': stop,
    'end': stop,
    'lutc': now,
    'now': now,
    'timestamp': now,
    'duration': stop - start,
    'offset': now - start,
  };
  final utcStart = DateTime.fromMillisecondsSinceEpoch(start * 1000, isUtc: true);
  String fmtDate(String spec, int ts) {
    final t = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
    return spec
        .replaceAll('Y', '${t.year}')
        .replaceAll('m', _two(t.month))
        .replaceAll('d', _two(t.day))
        .replaceAll('H', _two(t.hour))
        .replaceAll('M', _two(t.minute))
        .replaceAll('S', _two(t.second));
  }

  return template.replaceAllMapped(RegExp(r'\$?\{(\w+)(?::([^}]*))?\}'), (m) {
    final name = m[1]!;
    final arg = m[2];
    if (['utc', 'start', 'utcend', 'end'].contains(name) && arg != null && int.tryParse(arg) == null) {
      return fmtDate(arg, name == 'utc' || name == 'start' ? start : stop);
    }
    if ((name == 'duration' || name == 'offset') && arg != null && int.tryParse(arg) != null) {
      return '${values[name]! ~/ (int.parse(arg) == 0 ? 1 : int.parse(arg))}';
    }
    if (values.containsKey(name)) return '${values[name]}';
    switch (name) {
      case 'Y':
        return '${utcStart.year}';
      case 'm':
        return _two(utcStart.month);
      case 'd':
        return _two(utcStart.day);
      case 'H':
        return _two(utcStart.hour);
      case 'M':
        return _two(utcStart.minute);
      case 'S':
        return _two(utcStart.second);
    }
    return m[0]!;
  });
}

String? buildCatchupUrl(String url, String mode, String source, int start, int stop) {
  final i = url.indexOf('|');
  final base = i < 0 ? url : url.substring(0, i);
  final tail = i < 0 ? '' : url.substring(i);
  mode = mode.toLowerCase();
  final duration = stop - start;
  final xc = RegExp(r'^(https?://[^/]+(?:/[^/]+)*?)/(?:live/)?([^/]+)/([^/]+)/(\d+)(\.\w+)?$').firstMatch(base);
  if (mode == 'xc' || (mode.isEmpty && source.isEmpty && xc != null)) {
    if (xc != null) {
      final stamp = _stamp(DateTime.fromMillisecondsSinceEpoch(start * 1000));
      return '${xc[1]}/timeshift/${xc[2]}/${xc[3]}/${(duration ~/ 60).clamp(1, 100000)}/$stamp/${xc[4]}.ts$tail';
    }
  }
  String result;
  if (mode == 'append') {
    result = base + _fillTemplate(source, start, stop);
  } else if (mode == 'shift' || mode == 'timeshift') {
    result = '$base${base.contains('?') ? '&' : '?'}utc=$start&lutc=${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
  } else if (mode.startsWith('flussonic') || mode == 'fs') {
    if (base.contains('/mpegts')) {
      result = base.replaceFirst('/mpegts', '/timeshift_abs-$start.ts');
    } else {
      result = base.replaceFirstMapped(RegExp(r'/([\w\-]+)\.m3u8'), (m) => '/${m[1]}-$start-$duration.m3u8');
    }
  } else if (source.isNotEmpty) {
    result = source.startsWith('http') ? _fillTemplate(source, start, stop) : base + _fillTemplate(source, start, stop);
  } else {
    result = '$base${base.contains('?') ? '&' : '?'}utc=$start&lutc=${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
  }
  return result + tail;
}
