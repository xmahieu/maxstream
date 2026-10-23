import 'models.dart';
import 'provider.dart' show fold;

final _attrRe = RegExp(r'([\w\-]+)\s*=\s*"([^"]*)"');
final seriesRe = RegExp(r'^(.*?)[\s._\-|:]*\b[Ss](\d{1,2})[\s._\-]*[Ee](\d{1,4})\b(.*)$');
const _videoExts = ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.m4v', '.mpg', '.mpeg', '.webm', '.divx'];

class M3UEntry {
  final String name;
  final Map<String, String> attrs;
  final String group;
  final String url;
  M3UEntry(this.name, this.attrs, this.group, this.url);
}

class M3UData {
  final Map<String, String> header;
  final Map<Kind, List<Category>> cats;
  final Map<Kind, List<Item>> items;
  final Map<String, List<Episode>> episodes; // series id -> episodes
  M3UData(this.header, this.cats, this.items, this.episodes);

  Map<String, dynamic> toJson() => {
        'h': header,
        'c': {for (final k in Kind.values) k.name: [for (final c in cats[k] ?? <Category>[]) c.toJson()]},
        'i': {for (final k in Kind.values) k.name: [for (final i in items[k] ?? <Item>[]) i.toJson()]},
        'e': {for (final e in episodes.entries) e.key: [for (final ep in e.value) ep.toJson()]},
      };

  factory M3UData.fromJson(Map<String, dynamic> j) {
    final c = Map<String, dynamic>.from(j['c'] as Map);
    final i = Map<String, dynamic>.from(j['i'] as Map);
    final e = Map<String, dynamic>.from(j['e'] as Map);
    return M3UData(
      Map<String, String>.from(j['h'] as Map),
      {
        for (final k in Kind.values)
          k: [for (final x in (c[k.name] as List? ?? [])) Category.fromJson(Map<String, dynamic>.from(x as Map))]
      },
      {
        for (final k in Kind.values)
          k: [for (final x in (i[k.name] as List? ?? [])) Item.fromJson(Map<String, dynamic>.from(x as Map))]
      },
      {
        for (final en in e.entries)
          en.key: [for (final x in en.value as List) Episode.fromJson(Map<String, dynamic>.from(x as Map))]
      },
    );
  }
}

(String, String) _splitExtinf(String line) {
  final body = line.substring('#EXTINF:'.length);
  var inQuote = false;
  for (var i = 0; i < body.length; i++) {
    final ch = body[i];
    if (ch == '"') {
      inQuote = !inQuote;
    } else if (ch == ',' && !inQuote) {
      return (body.substring(0, i), body.substring(i + 1).trim());
    }
  }
  return (body, '');
}

Map<String, String> _attrs(String s) => {for (final m in _attrRe.allMatches(s)) m[1]!.toLowerCase(): m[2]!};

(Map<String, String>, List<M3UEntry>) parseM3U(String text) {
  final header = <String, String>{};
  final entries = <M3UEntry>[];
  String? name;
  Map<String, String> attrs = {};
  var groupHint = '';
  final opts = <String, String>{};
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTM3U')) {
      header.addAll(_attrs(line));
    } else if (line.startsWith('#EXTINF:')) {
      final (attrPart, title) = _splitExtinf(line);
      attrs = _attrs(attrPart);
      name = title.isNotEmpty ? title : (attrs['tvg-name'] ?? '');
    } else if (line.startsWith('#EXTGRP:')) {
      groupHint = line.substring(8).trim();
    } else if (line.startsWith('#EXTVLCOPT:')) {
      final kv = line.substring(11);
      final eq = kv.indexOf('=');
      if (eq > 0) opts[kv.substring(0, eq).trim().toLowerCase()] = kv.substring(eq + 1).trim();
    } else if (line.startsWith('#')) {
      continue;
    } else {
      final n = name ?? line.split('/').last;
      final group = attrs['group-title'] ?? (groupHint.isNotEmpty ? groupHint : '');
      entries.add(M3UEntry(n, attrs, group, _withHeaders(line, opts, attrs)));
      name = null;
      attrs = {};
      groupHint = '';
      opts.clear();
    }
  }
  return (header, entries);
}

String _withHeaders(String url, Map<String, String> opts, Map<String, String> attrs) {
  final h = <String>[];
  final ua = opts['http-user-agent'] ?? attrs['user-agent'] ?? attrs['http-user-agent'];
  final ref = opts['http-referrer'] ?? opts['http-referer'] ?? attrs['referer'];
  if (ua != null && ua.isNotEmpty) h.add('User-Agent=${Uri.encodeComponent(ua)}');
  if (ref != null && ref.isNotEmpty) h.add('Referer=${Uri.encodeComponent(ref)}');
  if (h.isEmpty) return url;
  return url + (url.contains('|') ? '&' : '|') + h.join('&');
}

Kind classify(M3UEntry e) {
  final path = e.url.split('|').first.split('?').first.toLowerCase();
  if (path.contains('/series/')) return Kind.series;
  if (path.contains('/movie/') || path.contains('/movies/')) return Kind.movie;
  if (_videoExts.any(path.endsWith)) return seriesRe.hasMatch(e.name) ? Kind.series : Kind.movie;
  return Kind.live;
}

M3UData buildM3U(String text) {
  final (header, entries) = parseM3U(text);
  final cats = {for (final k in Kind.values) k: <Category>[]};
  final items = {for (final k in Kind.values) k: <Item>[]};
  final episodes = <String, List<Episode>>{};
  final catIds = {for (final k in Kind.values) k: <String, String>{}};
  final shows = <String, Item>{};

  String catFor(Kind kind, String name) {
    name = name.isEmpty ? 'Uncategorised' : name;
    final map = catIds[kind]!;
    return map.putIfAbsent(name, () {
      final id = 'c${map.length}';
      cats[kind]!.add(Category(id, name));
      return id;
    });
  }

  final defMode = header['catchup'] ?? header['catchup-type'] ?? '';
  final defSource = header['catchup-source'] ?? '';
  final defDays = toInt(header['catchup-days']);
  var liveNum = 0;
  for (var idx = 0; idx < entries.length; idx++) {
    final e = entries[idx];
    final a = e.attrs;
    final kind = classify(e);
    final icon = a['tvg-logo'] ?? a['logo'] ?? '';
    final id = '$idx';
    if (kind == Kind.live) {
      liveNum++;
      final mode = a['catchup'] ?? a['catchup-type'] ?? defMode;
      final source = a['catchup-source'] ?? defSource;
      var days = toInt(a['catchup-days'] ?? a['timeshift'] ?? a['tvg-rec']);
      if (days == 0) days = defDays;
      final has = mode.isNotEmpty || source.isNotEmpty || days > 0;
      items[Kind.live]!.add(Item(
        kind: Kind.live,
        id: id,
        name: e.name,
        icon: icon,
        cat: catFor(Kind.live, e.group),
        epgId: a['tvg-id']?.isNotEmpty == true ? a['tvg-id']! : (a['tvg-name'] ?? ''),
        num: toInt(a['tvg-chno']) > 0 ? toInt(a['tvg-chno']) : liveNum,
        catchup: has,
        catchupDays: days > 0 ? days : (has ? 7 : 0),
        catchupMode: mode,
        catchupSource: source,
        url: e.url,
      ));
    } else if (kind == Kind.movie) {
      items[Kind.movie]!.add(Item(
        kind: Kind.movie,
        id: id,
        name: e.name,
        icon: icon,
        cat: catFor(Kind.movie, e.group),
        added: idx,
        year: yearOf(e.name),
        url: e.url,
      ));
    } else {
      final m = seriesRe.firstMatch(e.name);
      var show = e.name;
      var season = 1, episode = 1;
      if (m != null) {
        final s = m[1]!.trim().replaceAll(RegExp(r'^[\s\-_.|:]+|[\s\-_.|:]+$'), '');
        show = s.isEmpty ? e.name : s;
        season = int.parse(m[2]!);
        episode = int.parse(m[3]!);
      }
      final cat = catFor(Kind.series, e.group);
      final key = '$cat|${fold(show)}';
      var item = shows[key];
      if (item == null) {
        item = Item(kind: Kind.series, id: 's${shows.length}', name: show, icon: icon, cat: cat, added: idx, year: yearOf(show));
        shows[key] = item;
        items[Kind.series]!.add(item);
      }
      episodes.putIfAbsent(item.id, () => []).add(Episode(
            id: id,
            title: e.name,
            season: season,
            episode: episode,
            icon: icon,
            show: show,
            seriesId: item.id,
            url: e.url,
          ));
    }
  }
  return M3UData(header, cats, items, episodes);
}
