// Normalised data shared by the Xtream and M3U providers.

int toInt(dynamic v, [int def = 0]) {
  if (v == null) return def;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? double.tryParse(v.toString().trim())?.toInt() ?? def;
}

double toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim()) ?? 0;
}

String toStr(dynamic v) => v == null ? '' : (v is List ? (v.isEmpty ? '' : v.first.toString()) : v.toString());

int yearOf(dynamic v) {
  final m = RegExp(r'(19|20)\d{2}').firstMatch(toStr(v));
  return m == null ? 0 : int.parse(m.group(0)!);
}

enum Kind { live, movie, series }

class Playlist {
  String id;
  String name;
  String type; // xtream | m3u
  String server;
  String username;
  String password;
  String m3uUrl;
  String epgUrl;

  Playlist({
    required this.id,
    required this.name,
    required this.type,
    this.server = '',
    this.username = '',
    this.password = '',
    this.m3uUrl = '',
    this.epgUrl = '',
  });

  bool get isXtream => type == 'xtream';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'server': server,
        'username': username,
        'password': password,
        'm3uUrl': m3uUrl,
        'epgUrl': epgUrl,
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: toStr(j['id']),
        name: toStr(j['name']),
        type: toStr(j['type']),
        server: toStr(j['server']),
        username: toStr(j['username']),
        password: toStr(j['password']),
        m3uUrl: toStr(j['m3uUrl']),
        epgUrl: toStr(j['epgUrl']),
      );
}

class Category {
  final String id;
  final String name;
  const Category(this.id, this.name);
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Category.fromJson(Map<String, dynamic> j) => Category(toStr(j['id']), toStr(j['name']));
}

/// A channel, a movie or a series (episodes are [Episode]).
class Item {
  final Kind kind;
  final String id;
  final String name;
  final String icon;
  final String cat;
  final double rating;
  final int added;
  final int year;
  final String ext;
  final String plot;
  final String genre;
  final String backdrop;
  // live only
  final String epgId;
  final int num;
  final bool catchup;
  final int catchupDays;
  final String catchupMode;
  final String catchupSource;
  // m3u only: direct url (may carry |User-Agent=...)
  final String url;

  const Item({
    required this.kind,
    required this.id,
    required this.name,
    this.icon = '',
    this.cat = '',
    this.rating = 0,
    this.added = 0,
    this.year = 0,
    this.ext = '',
    this.plot = '',
    this.genre = '',
    this.backdrop = '',
    this.epgId = '',
    this.num = 0,
    this.catchup = false,
    this.catchupDays = 0,
    this.catchupMode = '',
    this.catchupSource = '',
    this.url = '',
  });

  String get key => '${kind.name}:$id';

  Map<String, dynamic> toJson() => {
        'k': kind.index,
        'id': id,
        'n': name,
        'i': icon,
        'c': cat,
        'r': rating,
        'a': added,
        'y': year,
        'e': ext,
        'p': plot,
        'g': genre,
        'b': backdrop,
        'ei': epgId,
        'nu': num,
        'cu': catchup,
        'cd': catchupDays,
        'cm': catchupMode,
        'cs': catchupSource,
        'u': url,
      };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        kind: Kind.values[toInt(j['k'])],
        id: toStr(j['id']),
        name: toStr(j['n']),
        icon: toStr(j['i']),
        cat: toStr(j['c']),
        rating: toDouble(j['r']),
        added: toInt(j['a']),
        year: toInt(j['y']),
        ext: toStr(j['e']),
        plot: toStr(j['p']),
        genre: toStr(j['g']),
        backdrop: toStr(j['b']),
        epgId: toStr(j['ei']),
        num: toInt(j['nu']),
        catchup: j['cu'] == true,
        catchupDays: toInt(j['cd']),
        catchupMode: toStr(j['cm']),
        catchupSource: toStr(j['cs']),
        url: toStr(j['u']),
      );
}

class Episode {
  final String id;
  final String title;
  final int season;
  final int episode;
  final String icon;
  final String plot;
  final int duration;
  final String ext;
  final String show;
  final String seriesId;
  final String url;

  const Episode({
    required this.id,
    required this.title,
    required this.season,
    required this.episode,
    this.icon = '',
    this.plot = '',
    this.duration = 0,
    this.ext = '',
    this.show = '',
    this.seriesId = '',
    this.url = '',
  });

  String get key => 'episode:$id';
  String get code => 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'id': id,
        't': title,
        's': season,
        'e': episode,
        'i': icon,
        'p': plot,
        'd': duration,
        'x': ext,
        'sh': show,
        'si': seriesId,
        'u': url,
      };

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: toStr(j['id']),
        title: toStr(j['t']),
        season: toInt(j['s']),
        episode: toInt(j['e']),
        icon: toStr(j['i']),
        plot: toStr(j['p']),
        duration: toInt(j['d']),
        ext: toStr(j['x']),
        show: toStr(j['sh']),
        seriesId: toStr(j['si']),
        url: toStr(j['u']),
      );
}

class SeriesDetail {
  final String name;
  final String plot;
  final String icon;
  final String backdrop;
  final String genre;
  final String cast;
  final String director;
  final double rating;
  final int year;
  final Map<int, List<Episode>> seasons;
  const SeriesDetail({
    required this.name,
    this.plot = '',
    this.icon = '',
    this.backdrop = '',
    this.genre = '',
    this.cast = '',
    this.director = '',
    this.rating = 0,
    this.year = 0,
    this.seasons = const {},
  });
}

class MovieDetail {
  final String name;
  final String plot;
  final String cast;
  final String director;
  final String genre;
  final int year;
  final int duration;
  final double rating;
  final String icon;
  final String backdrop;
  final String trailer;
  const MovieDetail({
    this.name = '',
    this.plot = '',
    this.cast = '',
    this.director = '',
    this.genre = '',
    this.year = 0,
    this.duration = 0,
    this.rating = 0,
    this.icon = '',
    this.backdrop = '',
    this.trailer = '',
  });
}

class Programme {
  final int start; // epoch seconds
  final int stop;
  final String title;
  final String desc;
  final bool archive;
  final String serverStart;
  const Programme(this.start, this.stop, this.title, {this.desc = '', this.archive = false, this.serverStart = ''});

  bool isNow(int now) => start <= now && now < stop;
  double progress(int now) => stop <= start ? 0 : ((now - start) / (stop - start)).clamp(0.0, 1.0);
}

/// What the player needs to open a stream.
class PlayRequest {
  final String url;
  final Map<String, String> headers;
  final String title;
  final String subtitle;
  final Kind kind; // live for channels and catch-up
  final bool isEpisode;
  final bool isCatchup;
  final String resumeKey; // '' = no resume tracking
  final Map<String, dynamic>? historyItem; // stored in "continue watching"
  final int startAt; // seconds
  const PlayRequest({
    required this.url,
    this.headers = const {},
    required this.title,
    this.subtitle = '',
    required this.kind,
    this.isEpisode = false,
    this.isCatchup = false,
    this.resumeKey = '',
    this.historyItem,
    this.startAt = 0,
  });
}

/// 'http://x/y.ts|User-Agent=a%20b&Referer=c' -> (url, headers)
(String, Map<String, String>) splitHeaders(String url) {
  final i = url.indexOf('|');
  if (i < 0) return (url, <String, String>{});
  final headers = <String, String>{};
  for (final part in url.substring(i + 1).split('&')) {
    final eq = part.indexOf('=');
    if (eq > 0) headers[part.substring(0, eq)] = Uri.decodeComponent(part.substring(eq + 1));
  }
  return (url.substring(0, i), headers);
}
