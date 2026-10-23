import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../play.dart';
import '../session.dart';
import '../store.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'live.dart';
import 'playlists.dart';
import 'search.dart';
import 'settings.dart';
import 'vod.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<Kind, int> _counts = {};
  late Timer _clock;
  String _time = '';

  @override
  void initState() {
    super.initState();
    Session.I.addListener(_reload);
    _tick();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Session.I.pl == null) _openPlaylists();
      _reload();
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    Session.I.removeListener(_reload);
    super.dispose();
  }

  void _tick() {
    final n = DateTime.now();
    setState(() => _time = '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}');
  }

  int _gen = 0;
  Future<void> _reload() async {
    final gen = ++_gen;
    if (!mounted) return;
    setState(() => _counts.clear());
    final prov = Session.I.prov;
    if (prov == null) return;
    for (final k in Kind.values) {
      try {
        final items = await Session.I.filter(k, await prov.allItems(k));
        if (gen != _gen || !mounted) return;
        setState(() => _counts[k] = items.length);
      } catch (_) {}
    }
  }

  Future<void> _openPlaylists() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlaylistsScreen()));
    _reload();
  }

  void _open(Widget screen) async {
    if (Session.I.prov == null) {
      _openPlaylists();
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pl = Session.I.pl;
    final cont = pl == null ? <(Map<String, dynamic>, Map<String, dynamic>)>[] : Store.continueWatching(pl.id);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 720;
          final pad = wide ? 40.0 : 16.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(pad, 12, pad, 24),
            children: [
              Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset('assets/icon.png', width: 44, height: 44)),
                const SizedBox(width: 12),
                const Text('MaxStream', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(width: 12),
                if (pl != null && wide) Flexible(child: Text(pl.name, style: const TextStyle(color: C.muted), overflow: TextOverflow.ellipsis)),
                const Spacer(),
                if (wide) Text(_time, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                IconBtn(Icons.star_rounded, () => _open(const DonateScreen()), color: C.star, tooltip: t('donate')),
                IconBtn(Icons.settings, () => _open(const SettingsScreen()), tooltip: t('settings')),
              ]),
              const SizedBox(height: 22),
              _tiles(wide),
              const SizedBox(height: 18),
              _shortcuts(wide),
              if (cont.isNotEmpty) ...[
                const SizedBox(height: 26),
                Text(t('continue'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SizedBox(
                  height: wide ? 190 : 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: cont.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, i) => _continueCard(cont[i].$1, cont[i].$2, wide),
                  ),
                ),
              ],
            ],
          );
        }),
      ),
    );
  }

  Widget _tiles(bool wide) {
    Widget tile(Kind kind, String label, IconData icon, Color color, String sub, Widget screen, {bool first = false}) {
      return Expanded(
        child: Tappable(
          autofocus: first,
          radius: 22,
          onTap: () => _open(screen),
          builder: (_, f) => AnimatedScale(
            scale: f ? 1.03 : 1,
            duration: const Duration(milliseconds: 120),
            child: Container(
              height: wide ? 200 : 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(19),
                gradient: LinearGradient(
                    colors: [color, Color.lerp(color, Colors.black, 0.35)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              padding: EdgeInsets.all(wide ? 22 : 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: wide ? 56 : 34, color: Colors.white),
                const Spacer(),
                Text(label, style: TextStyle(fontSize: wide ? 26 : 16, fontWeight: FontWeight.w800)),
                if (wide) Text(sub, style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          ),
        ),
      );
    }

    String count(Kind k, String key) => _counts[k] == null ? t('loading') : tf(key, _counts[k]!);
    return Row(children: [
      tile(Kind.live, t('live'), Icons.live_tv_rounded, C.liveTile, count(Kind.live, 'channels_n'), const LiveScreen(), first: true),
      SizedBox(width: wide ? 20 : 10),
      tile(Kind.movie, t('movies'), Icons.movie_rounded, C.movieTile, count(Kind.movie, 'movies_n'), const VodScreen(kind: Kind.movie)),
      SizedBox(width: wide ? 20 : 10),
      tile(Kind.series, t('series'), Icons.video_library_rounded, C.seriesTile, count(Kind.series, 'series_n'),
          const VodScreen(kind: Kind.series)),
    ]);
  }

  Widget _shortcuts(bool wide) {
    final items = <(IconData, Color, String, VoidCallback)>[
      (Icons.history_rounded, C.teal, t('catchup'), () => _open(const LiveScreen(catchupOnly: true))),
      (Icons.view_list_rounded, const Color(0xFFB0306A), t('guide'), () => _open(const LiveScreen())),
      (Icons.favorite_rounded, const Color(0xFFC26A12), t('favourites'), () => _open(const LiveScreen(favourites: true))),
      (Icons.search_rounded, const Color(0xFF3949AB), t('search'), () => _open(const SearchScreen())),
      (Icons.playlist_play_rounded, const Color(0xFF6D4C41), t('playlists'), _openPlaylists),
      (Icons.person_rounded, const Color(0xFF00838F), t('account'), () => _open(const AccountScreen())),
    ];
    return Wrap(spacing: 12, runSpacing: 12, children: [
      for (final it in items)
        SizedBox(
          width: wide ? null : 160,
          child: Tappable(
            radius: 16,
            onTap: it.$4,
            builder: (_, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: f ? C.cardFocus : C.card, borderRadius: BorderRadius.circular(13)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: it.$2, borderRadius: BorderRadius.circular(9)),
                  child: Icon(it.$1, size: 20),
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(it.$3, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _continueCard(Map<String, dynamic> entry, Map<String, dynamic> state, bool wide) {
    final item = Map<String, dynamic>.from(entry['item'] as Map);
    final key = toStr(entry['key']);
    final pos = toInt(state['pos']), total = toInt(state['total']);
    final isEp = key.startsWith('episode:');
    final title = isEp ? '${toStr(item['show'])} ${toStr(item['code'])}' : toStr(item['name']);
    return SizedBox(
      width: wide ? 300 : 230,
      child: Tappable(
        radius: 16,
        onTap: () async {
          await resumeFromHistory(context, item, key, pos);
          if (mounted) setState(() {});
        },
        onLongPress: () async {
          await Store.removeHistory(Session.I.pl!.id, key);
          if (mounted) setState(() {});
        },
        builder: (_, f) => Container(
          decoration: BoxDecoration(color: f ? C.cardFocus : C.card, borderRadius: BorderRadius.circular(13)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: NetImage(toStr(item['backdrop']).isNotEmpty ? toStr(item['backdrop']) : toStr(item['icon']))),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: SizedBox(height: 20, child: Marquee(title, active: f, style: const TextStyle(fontWeight: FontWeight.bold))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(children: [
                Expanded(child: Thin(total > 0 ? pos / total : 0)),
                const SizedBox(width: 8),
                Text(tf('left', fmtDuration(total - pos)), style: const TextStyle(color: C.muted, fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
