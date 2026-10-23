import 'package:flutter/material.dart';

import '../models.dart';
import '../provider.dart';
import '../session.dart';
import '../store.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});
  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  List<Playlist> _list = [];

  @override
  void initState() {
    super.initState();
    _list = Store.playlists();
  }

  Future<void> _edit([Playlist? pl]) async {
    final saved = await Navigator.of(context).push<Playlist>(MaterialPageRoute(builder: (_) => PlaylistForm(playlist: pl)));
    if (saved == null) return;
    final list = Store.playlists();
    final idx = list.indexWhere((p) => p.id == saved.id);
    if (idx >= 0) {
      list[idx] = saved;
    } else {
      list.add(saved);
    }
    await Store.savePlaylists(list);
    await Store.clearCache('${saved.id}_');
    Session.I.activate(saved);
    if (!mounted) return;
    if (pl == null) {
      Navigator.of(context).pop(); // first playlist: go straight home
      return;
    }
    setState(() => _list = Store.playlists());
  }

  Future<void> _delete(Playlist pl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${t('delete')} « ${pl.name} » ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('cancel'))),
          TextButton(autofocus: true, onPressed: () => Navigator.pop(c, true), child: Text(t('delete'))),
        ],
      ),
    );
    if (ok != true) return;
    final list = Store.playlists()..removeWhere((p) => p.id == pl.id);
    await Store.savePlaylists(list);
    await Store.clearCache('${pl.id}_');
    if (Store.activeId == pl.id && list.isNotEmpty) Store.activeId = list.first.id;
    Session.I.load();
    setState(() => _list = list);
  }

  @override
  Widget build(BuildContext context) {
    final active = Session.I.pl?.id;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Header(t('playlists'), actions: [IconBtn(Icons.add, () => _edit(), tooltip: t('add_playlist'))]),
          Expanded(
            child: _list.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('assets/icon.png', width: 96)),
                      const SizedBox(height: 18),
                      Text(t('welcome'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(t('welcome_sub'), textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
                      const SizedBox(height: 22),
                      Btn(t('add_playlist'), () => _edit(), icon: Icons.add, autofocus: true, primary: true),
                    ]),
                  )
                : ListView(padding: const EdgeInsets.all(16), children: [
                    for (final (i, pl) in _list.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Tappable(
                          autofocus: i == 0,
                          radius: 16,
                          onTap: () {
                            Session.I.activate(pl);
                            Navigator.of(context).pop();
                          },
                          onLongPress: () => _edit(pl),
                          builder: (_, f) => Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: f ? C.cardFocus : C.card, borderRadius: BorderRadius.circular(13)),
                            child: Row(children: [
                              Icon(pl.isXtream ? Icons.dns_rounded : Icons.list_alt_rounded, color: C.accent),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(pl.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  Text(pl.isXtream ? '${t('xtream')} · ${pl.username}' : t('m3u'),
                                      style: const TextStyle(color: C.muted)),
                                ]),
                              ),
                              if (pl.id == active) const Icon(Icons.check_circle, color: C.accent),
                              IconBtn(Icons.edit, () => _edit(pl), tooltip: t('edit')),
                              IconBtn(Icons.delete_outline, () => _delete(pl), tooltip: t('delete')),
                            ]),
                          ),
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

class PlaylistForm extends StatefulWidget {
  final Playlist? playlist;
  const PlaylistForm({super.key, this.playlist});
  @override
  State<PlaylistForm> createState() => _PlaylistFormState();
}

class _PlaylistFormState extends State<PlaylistForm> {
  late bool _xtream = widget.playlist?.isXtream ?? true;
  late final _name = TextEditingController(text: widget.playlist?.name ?? '');
  late final _server = TextEditingController(text: widget.playlist?.server ?? '');
  late final _user = TextEditingController(text: widget.playlist?.username ?? '');
  late final _pass = TextEditingController(text: widget.playlist?.password ?? '');
  late final _m3u = TextEditingController(text: widget.playlist?.m3uUrl ?? '');
  late final _epg = TextEditingController(text: widget.playlist?.epgUrl ?? '');
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    var server = _server.text.trim(), user = _user.text.trim(), pass = _pass.text.trim();
    var m3u = _m3u.text.trim();
    var xtream = _xtream;
    // a get.php link pasted as M3U is really an Xtream account
    final link = parseXtreamLink(xtream ? server : m3u);
    if (link != null) {
      xtream = true;
      server = link.$1;
      user = link.$2;
      pass = link.$3;
    }
    if (xtream && (server.isEmpty || user.isEmpty) || !xtream && m3u.isEmpty) return;
    final pl = Playlist(
      id: widget.playlist?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _name.text.trim().isEmpty ? (xtream ? Uri.tryParse(normalizeServer(server))?.host ?? 'IPTV' : 'M3U') : _name.text.trim(),
      type: xtream ? 'xtream' : 'm3u',
      server: xtream ? normalizeServer(server) : '',
      username: user,
      password: pass,
      m3uUrl: xtream ? '' : m3u,
      epgUrl: _epg.text.trim(),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await providerFor(pl).check();
      if (mounted) Navigator.of(context).pop(pl);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = errorText(e);
      });
    }
  }

  Widget _field(TextEditingController c, String label, {bool secret = false, bool autofocus = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: c,
          autofocus: autofocus,
          obscureText: secret,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Header(widget.playlist == null ? t('add_playlist') : widget.playlist!.name),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Row(children: [
                    for (final x in [true, false])
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: x ? 6 : 0, left: x ? 0 : 6),
                          child: Tappable(
                            radius: 16,
                            onTap: () => setState(() => _xtream = x),
                            builder: (_, f) => Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: _xtream == x ? C.accent : (f ? C.cardFocus : C.card), borderRadius: BorderRadius.circular(13)),
                              child: Text(x ? t('xtream') : t('m3u'),
                                  style: TextStyle(fontWeight: FontWeight.bold, color: _xtream == x ? C.bg : C.text)),
                            ),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 20),
                  _field(_name, t('name'), autofocus: widget.playlist == null),
                  if (_xtream) ...[
                    _field(_server, t('server')),
                    _field(_user, t('username')),
                    _field(_pass, t('password'), secret: true),
                  ] else
                    _field(_m3u, t('m3u_url')),
                  _field(_epg, t('epg_url')),
                  if (_error != null)
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: C.live))),
                  _busy
                      ? Row(children: [
                          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)),
                          const SizedBox(width: 12),
                          Text(t('checking')),
                        ])
                      : Align(alignment: Alignment.centerLeft, child: Btn(t('save'), _save, icon: Icons.check, primary: true)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
