import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models.dart';
import '../play.dart';
import '../session.dart';
import '../store.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'guide.dart';
import 'player.dart';

const _all = '__all', _fav = '__fav', _recent = '__recent';

class LiveScreen extends StatefulWidget {
  final bool catchupOnly;
  final bool favourites;
  const LiveScreen({super.key, this.catchupOnly = false, this.favourites = false});
  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  List<Item> _allChannels = [];
  List<Category> _cats = [];
  Map<String, int> _counts = {};
  String _cat = _all;
  List<Item> _channels = [];
  Item? _selected;
  String _query = '';
  Object? _error;
  bool _loading = true;

  Player? _preview;
  VideoController? _previewVideo;
  String? _previewId;

  @override
  void initState() {
    super.initState();
    _cat = widget.favourites ? _fav : _all;
    Session.I.addListener(_epgChanged);
    _load();
  }

  @override
  void dispose() {
    Session.I.removeListener(_epgChanged);
    Session.I.forgetQueuedEpg();
    _preview?.dispose();
    super.dispose();
  }

  void _epgChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = Session.I;
      var all = await s.filter(Kind.live, await s.prov!.allItems(Kind.live));
      if (widget.catchupOnly) all = all.where((c) => c.catchup).toList();
      final cats = await s.categories(Kind.live);
      final counts = <String, int>{};
      for (final c in all) {
        counts[c.cat] = (counts[c.cat] ?? 0) + 1;
      }
      setState(() {
        _allChannels = all;
        _cats = cats.where((c) => (counts[c.id] ?? 0) > 0).toList();
        _counts = counts;
        _loading = false;
      });
      _selectCat(_cat);
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _selectCat(String id) {
    final pid = Session.I.pl!.id;
    List<Item> list;
    if (id == _all) {
      list = _allChannels;
    } else if (id == _fav) {
      list = Store.favourites(pid, Kind.live);
    } else if (id == _recent) {
      list = Store.recentChannels(pid);
    } else {
      list = _allChannels.where((c) => c.cat == id).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    setState(() {
      _cat = id;
      _channels = list;
    });
  }

  Future<void> _startPreview(Item ch) async {
    if (_preview == null) {
      _preview = Player(configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024));
      _previewVideo = VideoController(_preview!);
    }
    final req = channelRequest(ch);
    setState(() => _previewId = ch.id);
    await Store.addRecentChannel(Session.I.pl!.id, ch);
    await configurePlayer(_preview!, req.headers);
    await _preview!.open(Media(req.url, httpHeaders: req.headers));
  }

  Future<void> _stopPreview() async {
    if (_preview != null) {
      await _preview!.stop();
    }
    if (mounted) setState(() => _previewId = null);
  }

  Future<void> _fullscreen(Item ch) async {
    await _stopPreview(); // providers often allow a single connection
    if (!mounted) return;
    await playChannel(context, ch, zapList: _channels);
    if (mounted) setState(() {});
  }

  Future<void> _onChannel(Item ch, bool wide) async {
    setState(() => _selected = ch);
    if (!wide) {
      await _fullscreen(ch);
    } else if (_previewId == ch.id) {
      await _fullscreen(ch);
    } else {
      await _startPreview(ch);
    }
  }

  Future<void> _guide(Item ch) async {
    await _stopPreview();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuideScreen(channel: ch, zapList: _channels)));
  }

  Future<void> _toggleFav(Item ch) async {
    await Store.toggleFavourite(Session.I.pl!.id, ch);
    if (_cat == _fav) _selectCat(_fav);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          return Column(children: [
            Header(widget.catchupOnly ? t('catchup') : t('live'), actions: [
              SizedBox(
                width: wide ? 360 : 170,
                child: TextField(
                  decoration: InputDecoration(hintText: t('search_hint'), prefixIcon: const Icon(Icons.search), isDense: true),
                  onChanged: (v) {
                    _query = v.trim();
                    _selectCat(_cat);
                  },
                ),
              ),
            ]),
            Expanded(
              child: _loading
                  ? const Loading()
                  : _error != null
                      ? Message(errorText(_error!), icon: Icons.error_outline, onRetry: _load)
                      : wide
                          ? _wide()
                          : _narrow(),
            ),
          ]);
        }),
      ),
    );
  }

  List<(String, String, int)> _catEntries() {
    final pid = Session.I.pl!.id;
    return [
      (_all, t('all'), _allChannels.length),
      (_fav, t('favourites'), Store.favourites(pid, Kind.live).length),
      (_recent, t('recent'), Store.recentChannels(pid).length),
      for (final c in _cats) (c.id, c.name, _counts[c.id] ?? 0),
    ];
  }

  Widget _narrow() {
    final cats = _catEntries();
    return Column(children: [
      SizedBox(
        height: 54,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          scrollDirection: Axis.horizontal,
          itemCount: cats.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final c = cats[i];
            final sel = c.$1 == _cat;
            return Tappable(
              radius: 20,
              onTap: () => _selectCat(c.$1),
              builder: (_, f) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: sel ? C.sel : C.card, borderRadius: BorderRadius.circular(18)),
                child: Text('${c.$2}  ${c.$3}', style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
              ),
            );
          },
        ),
      ),
      Expanded(child: _channelList(false)),
    ]);
  }

  Widget _wide() {
    final cats = _catEntries();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 300,
          decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(20)),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: cats.length,
            itemBuilder: (_, i) {
              final c = cats[i];
              final sel = c.$1 == _cat;
              return Tappable(
                autofocus: i == 0 && _selected == null,
                radius: 14,
                onTap: () => _selectCat(c.$1),
                onFocus: (f) {
                  if (f) _selectCat(c.$1);
                },
                builder: (_, f) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: sel ? C.sel : Colors.transparent, borderRadius: BorderRadius.circular(11)),
                  child: Row(children: [
                    Expanded(child: SizedBox(height: 22, child: Marquee(c.$2, active: f, style: const TextStyle(fontSize: 17)))),
                    Text('${c.$3}', style: const TextStyle(color: C.muted)),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(20)),
            child: _channelList(true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(flex: 5, child: _previewPanel()),
      ]),
    );
  }

  Widget _channelList(bool wide) {
    if (_channels.isEmpty) return Message(t('no_items'));
    final s = Session.I;
    final now = s.nowSec;
    final pid = s.pl!.id;
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _channels.length,
      itemExtent: 84,
      itemBuilder: (_, i) {
        final ch = _channels[i];
        s.requestEpg(ch);
        final epg = s.epgFor(ch);
        final cur = epg?.where((p) => p.isNow(now)).firstOrNull;
        final fav = Store.isFavourite(pid, ch.key);
        return Tappable(
          radius: 14,
          onTap: () => _onChannel(ch, wide),
          onLongPress: () => _toggleFav(ch),
          onFocus: (f) {
            if (f && wide) setState(() => _selected = ch);
          },
          builder: (_, f) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: _previewId == ch.id ? C.sel : (f ? C.cardFocus : Colors.transparent), borderRadius: BorderRadius.circular(11)),
            child: Row(children: [
              SizedBox(
                  width: 44, child: Text('${ch.num > 0 ? ch.num : i + 1}', style: const TextStyle(color: C.muted, fontSize: 15))),
              ChannelLogo(ch),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: SizedBox(
                            height: 24,
                            child: Marquee(ch.name, active: f, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
                    if (fav) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.favorite, size: 16, color: C.star)),
                    if (ch.catchup) Padding(padding: const EdgeInsets.only(left: 6), child: Pill(t('replay'))),
                  ]),
                  if (cur != null) ...[
                    const SizedBox(height: 2),
                    Text('${fmtClock(cur.start)}  ${cur.title}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 14)),
                    const SizedBox(height: 4),
                    Thin(cur.progress(now), height: 3),
                  ],
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _previewPanel() {
    final ch = _selected;
    final now = Session.I.nowSec;
    final epg = ch == null ? null : Session.I.epgFor(ch);
    final cur = epg?.where((p) => p.isNow(now)).firstOrNull;
    final next = epg?.where((p) => p.start >= (cur?.stop ?? now)).take(2).toList() ?? [];
    final fav = ch != null && Store.isFavourite(Session.I.pl!.id, ch.key);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFF05080F), borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: _previewId != null && _previewVideo != null
              ? GestureDetector(
                  onTap: () => ch != null ? _fullscreen(ch) : null,
                  child: Video(controller: _previewVideo!, controls: NoVideoControls))
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.live_tv_rounded, size: 56, color: C.dim),
                  const SizedBox(height: 10),
                  Text(t('preview_hint'), style: const TextStyle(color: C.dim)),
                ]),
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(20)),
          child: ch == null
              ? const SizedBox.shrink()
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(cur?.title ?? ch.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                    if (cur != null) Text('${fmtClock(cur.start)} - ${fmtClock(cur.stop)}', style: const TextStyle(fontSize: 18)),
                  ]),
                  if (cur != null) ...[const SizedBox(height: 8), Thin(cur.progress(now))],
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(cur?.desc.isNotEmpty == true ? cur!.desc : (epg == null ? t('loading') : (cur == null ? t('no_epg') : '')),
                          style: const TextStyle(color: Color(0xFFD2DCEB), fontSize: 15)),
                    ),
                  ),
                  if (next.isNotEmpty) ...[
                    Text(t('up_next'), style: const TextStyle(color: C.muted, fontWeight: FontWeight.bold)),
                    for (final p in next)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${fmtClock(p.start)}    ${p.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    const SizedBox(height: 10),
                  ],
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    Btn(t('fullscreen'), () => _fullscreen(ch), icon: Icons.fullscreen, primary: true),
                    Btn(t('guide'), () => _guide(ch), icon: Icons.view_list_rounded),
                    Btn(fav ? t('fav_remove') : t('fav_add'), () => _toggleFav(ch), icon: fav ? Icons.favorite : Icons.favorite_border),
                  ]),
                ]),
        ),
      ),
    ]);
  }
}
