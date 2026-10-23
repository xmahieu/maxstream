import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../play.dart';
import '../session.dart';
import '../store.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';

final _epCodeRe = RegExp(r'\b[Ss]\d{1,2}\s*[Ee]\d{1,4}\b|\b\d{1,2}x\d{1,3}\b');

String episodeTitle(Episode e) {
  var title = e.title;
  if (e.show.isNotEmpty && title.toLowerCase().startsWith(e.show.toLowerCase())) title = title.substring(e.show.length);
  title = title.replaceAll(_epCodeRe, ' ').replaceAll(RegExp(r'\s{2,}'), ' ');
  title = title.replaceAll(RegExp(r'^[\s\-|:._]+|[\s\-|:._]+$'), '');
  return title.isEmpty ? tf('episode_n', e.episode) : title;
}

class DetailScreen extends StatefulWidget {
  final Item item;
  final List<Item> siblings;
  const DetailScreen({super.key, required this.item, this.siblings = const []});
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late Item _item = widget.item;
  MovieDetail? _movie;
  SeriesDetail? _series;
  int _season = -1;
  Object? _error;

  bool get _isMovie => _item.kind == Kind.movie;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _movie = null;
      _series = null;
      _error = null;
    });
    try {
      if (_isMovie) {
        final m = await Session.I.prov!.movieDetail(_item);
        setState(() => _movie = m);
      } else {
        final s = await Session.I.prov!.seriesDetail(_item);
        setState(() {
          _series = s;
          _season = _nextEpisode()?.season ?? (s.seasons.keys.isEmpty ? -1 : s.seasons.keys.first);
        });
      }
    } catch (e) {
      setState(() => _error = e);
    }
  }

  Map<String, dynamic>? _resume(String key) => Store.resumeOf(Session.I.pl!.id, key);

  /// Episode in progress, else the first not yet watched.
  Episode? _nextEpisode() {
    final s = _series;
    if (s == null) return null;
    Episode? fallback;
    for (final eps in s.seasons.values) {
      for (final e in eps) {
        final r = _resume(e.key);
        if (r != null && toInt(r['pos']) > 0 && r['watched'] != true) return e;
        if (fallback == null && !(r != null && r['watched'] == true)) fallback = e;
      }
    }
    return fallback ?? (s.seasons.values.isEmpty ? null : s.seasons.values.first.firstOrNull);
  }

  String get _title => _movie?.name.isNotEmpty == true ? _movie!.name : (_series?.name ?? _item.name);
  String get _poster =>
      (_movie?.icon.isNotEmpty == true ? _movie!.icon : null) ?? (_series?.icon.isNotEmpty == true ? _series!.icon : _item.icon);
  String get _backdrop =>
      (_movie?.backdrop.isNotEmpty == true ? _movie!.backdrop : null) ??
      (_series?.backdrop.isNotEmpty == true ? _series!.backdrop : _item.backdrop);

  @override
  Widget build(BuildContext context) {
    final loaded = _movie != null || _series != null;
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        if (_backdrop.isNotEmpty) Opacity(opacity: 0.25, child: NetImage(_backdrop)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x880B1220), C.bg], stops: [0, 0.7]),
          ),
        ),
        SafeArea(
          child: Column(children: [
            Header(_isMovie ? t('movies') : t('series')),
            Expanded(
              child: _error != null
                  ? Message(errorText(_error!), onRetry: _load)
                  : !loaded
                      ? const Loading()
                      : LayoutBuilder(builder: (context, box) => _body(box.maxWidth >= 800)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _body(bool wide) {
    final pid = Session.I.pl!.id;
    final fav = Store.isFavourite(pid, _item.key);
    final meta = <String>[
      if ((_movie?.rating ?? _series?.rating ?? _item.rating) > 0)
        '★ ${(_movie?.rating ?? _series?.rating ?? _item.rating).toStringAsFixed(1)}',
      if ((_movie?.year ?? _series?.year ?? 0) > 0 || _item.year > 0)
        '${(_movie?.year ?? _series?.year ?? 0) > 0 ? (_movie?.year ?? _series?.year) : _item.year}',
      if ((_movie?.duration ?? 0) > 0) fmtDuration(_movie!.duration),
      if ((_movie?.genre ?? _series?.genre ?? '').isNotEmpty) (_movie?.genre ?? _series!.genre),
      if (_series != null && _series!.seasons.isNotEmpty) '${_series!.seasons.length} ${t('seasons').toLowerCase()}',
    ];
    final plot = (_movie?.plot.isNotEmpty == true ? _movie!.plot : null) ?? (_series?.plot.isNotEmpty == true ? _series!.plot : _item.plot);
    final director = _movie?.director ?? _series?.director ?? '';
    final cast = _movie?.cast ?? _series?.cast ?? '';

    final buttons = <Widget>[];
    if (_isMovie) {
      final r = _resume(_item.key);
      final pos = r == null || r['watched'] == true ? 0 : toInt(r['pos']);
      buttons.add(Btn(pos > 30 ? tf('resume_at', fmtDuration(pos)) : t('play'), () async {
        await playMovie(context, _item, startAt: pos > 30 ? pos : 0);
        setState(() {});
      }, icon: Icons.play_arrow_rounded, autofocus: true, primary: true));
      if (pos > 30) {
        buttons.add(Btn(t('from_start'), () async {
          await playMovie(context, _item, startAt: 0);
          setState(() {});
        }, icon: Icons.replay_rounded));
      }
      if (_movie!.trailer.isNotEmpty) {
        buttons.add(Btn(t('trailer'), () {
          launchUrl(Uri.parse('https://www.youtube.com/watch?v=${_movie!.trailer}'), mode: LaunchMode.externalApplication);
        }, icon: Icons.ondemand_video_rounded));
      }
    } else {
      final next = _nextEpisode();
      if (next != null) {
        final r = _resume(next.key);
        final pos = r == null || r['watched'] == true ? 0 : toInt(r['pos']);
        buttons.add(Btn(pos > 30 ? tf('resume_ep', next.code) : tf('play_ep', next.code), () async {
          await playEpisode(context, next, showIcon: _poster, backdrop: _backdrop, startAt: pos > 30 ? pos : 0);
          setState(() {});
        }, icon: Icons.play_arrow_rounded, autofocus: true, primary: true));
      }
    }
    buttons.add(Btn(fav ? t('fav_remove') : t('fav_add'), () async {
      await Store.toggleFavourite(pid, _item);
      setState(() {});
    }, icon: fav ? Icons.favorite : Icons.favorite_border));

    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_title, style: TextStyle(fontSize: wide ? 36 : 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(meta.join('   •   '), style: const TextStyle(color: Color(0xFFC4D0E3), fontSize: 16)),
      const SizedBox(height: 14),
      if (plot.isNotEmpty)
        Text(plot, maxLines: wide ? 6 : 8, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFD2DCEB), fontSize: 16, height: 1.4)),
      if (director.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text.rich(TextSpan(children: [
          TextSpan(text: '${t('director')}   ', style: const TextStyle(color: C.muted)),
          TextSpan(text: director),
        ])),
      ],
      if (cast.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text.rich(
            TextSpan(children: [TextSpan(text: '${t('cast')}   ', style: const TextStyle(color: C.muted)), TextSpan(text: cast)]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ],
      const SizedBox(height: 20),
      Wrap(spacing: 12, runSpacing: 12, children: buttons),
    ]);

    final poster = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(width: wide ? 260 : 130, height: wide ? 390 : 195, child: NetImage(_poster)),
    );

    return ListView(padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 16, vertical: 10), children: [
      wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [poster, const SizedBox(width: 36), Expanded(child: info)])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [poster, const SizedBox(height: 16), info]),
      const SizedBox(height: 28),
      if (_isMovie && widget.siblings.length > 1) ..._related(wide),
      if (!_isMovie) ..._seasons(wide),
    ]);
  }

  List<Widget> _related(bool wide) {
    final others = widget.siblings.where((s) => s.id != _item.id).toList();
    return [
      Text(t('movies'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      SizedBox(
        height: wide ? 270 : 210,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: others.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, i) => SizedBox(
            width: wide ? 160 : 120,
            child: PosterCard(others[i], onTap: () {
              setState(() => _item = others[i]);
              _load();
            }),
          ),
        ),
      ),
    ];
  }

  List<Widget> _seasons(bool wide) {
    final s = _series!;
    if (s.seasons.isEmpty) return [Message(t('no_items'))];
    final eps = s.seasons[_season] ?? s.seasons.values.first;
    return [
      SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: s.seasons.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final n = s.seasons.keys.elementAt(i);
            final sel = n == _season;
            return Tappable(
              radius: 20,
              onTap: () => setState(() => _season = n),
              onFocus: (f) {
                if (f) setState(() => _season = n);
              },
              builder: (_, f) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(color: sel ? C.accent : C.card, borderRadius: BorderRadius.circular(18)),
                child: Text(tf('season_n', n), style: TextStyle(color: sel ? C.bg : C.text, fontWeight: FontWeight.bold)),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 14),
      SizedBox(
        height: wide ? 240 : 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: eps.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, i) => _episodeCard(eps[i], wide),
        ),
      ),
    ];
  }

  Widget _episodeCard(Episode e, bool wide) {
    final r = _resume(e.key);
    final total = toInt(r?['total']);
    final watched = r?['watched'] == true;
    final progress = watched ? 1.0 : (total > 0 ? toInt(r?['pos']) / total : 0.0);
    return SizedBox(
      width: wide ? 300 : 230,
      child: Tappable(
        radius: 16,
        onTap: () async {
          await playEpisode(context, e, showIcon: _poster, backdrop: _backdrop);
          setState(() {});
        },
        builder: (_, f) => Container(
          decoration: BoxDecoration(color: f ? C.cardFocus : C.card, borderRadius: BorderRadius.circular(13)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                NetImage(e.icon,
                    placeholder: Container(
                        color: C.track,
                        alignment: Alignment.center,
                        child: Text('E${e.episode.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF55657F))))),
                if (e.icon.isNotEmpty)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Pill('E${e.episode.toString().padLeft(2, '0')}', color: Colors.black54),
                  ),
                if (watched) const Positioned(right: 8, top: 8, child: Icon(Icons.check_circle, color: C.accent)),
                if (progress > 0) Positioned(left: 8, right: 8, bottom: 8, child: Thin(progress)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                  height: 22,
                  child: Marquee(episodeTitle(e), active: f, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            ),
          ]),
        ),
      ),
    );
  }
}
