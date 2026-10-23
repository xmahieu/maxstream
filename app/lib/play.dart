import 'package:flutter/material.dart';

import 'models.dart';
import 'screens/player.dart';
import 'session.dart';
import 'store.dart';
import 'strings.dart';
import 'theme.dart';
import 'widgets.dart';

/// Resume point (seconds) or 0, asking "resume / from start" when one exists.
Future<int?> askResume(BuildContext context, String key) async {
  final pl = Session.I.pl;
  if (pl == null) return 0;
  final r = Store.resumeOf(pl.id, key);
  final pos = r == null || r['watched'] == true ? 0 : toInt(r['pos']);
  if (pos < 30) return 0;
  return showDialog<int>(
    context: context,
    builder: (c) => SimpleDialog(
      backgroundColor: C.panel,
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c, pos),
          child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(tf('resume_at', fmtDuration(pos)), style: const TextStyle(fontSize: 18))),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c, 0),
          child: Padding(padding: const EdgeInsets.all(8), child: Text(t('from_start'), style: const TextStyle(fontSize: 18))),
        ),
      ],
    ),
  );
}

Future<void> openPlayer(BuildContext context, PlayRequest req, {List<Item> zapList = const [], Item? channel}) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PlayerScreen(request: req, zapList: zapList, channel: channel),
  ));
}

PlayRequest channelRequest(Item ch) {
  final (url, headers) = splitHeaders(Session.I.prov!.streamUrl(ch));
  return PlayRequest(url: url, headers: headers, title: ch.name, kind: Kind.live);
}

Future<void> playChannel(BuildContext context, Item ch, {List<Item> zapList = const []}) async {
  await Store.addRecentChannel(Session.I.pl!.id, ch);
  if (!context.mounted) return;
  await openPlayer(context, channelRequest(ch), zapList: zapList, channel: ch);
}

Future<void> playCatchup(BuildContext context, Item ch, Programme p) async {
  final raw = Session.I.prov!.catchupUrl(ch, p);
  if (raw == null) {
    toast(context, t('no_catchup'));
    return;
  }
  final (url, headers) = splitHeaders(raw);
  await openPlayer(
      context,
      PlayRequest(
          url: url,
          headers: headers,
          title: p.title,
          subtitle: '${ch.name} · ${fmtClock(p.start)}',
          kind: Kind.live,
          isCatchup: true));
}

Map<String, dynamic> movieHistory(Item m) => {'type': 'movie', 'item': m.toJson(), 'name': m.name, 'icon': m.icon, 'backdrop': m.backdrop};

Map<String, dynamic> episodeHistory(Episode e, String showIcon, String backdrop) =>
    {'type': 'episode', 'ep': e.toJson(), 'show': e.show, 'code': e.code, 'icon': e.icon.isNotEmpty ? e.icon : showIcon, 'backdrop': backdrop};

Future<void> playMovie(BuildContext context, Item m, {int? startAt}) async {
  final start = startAt ?? await askResume(context, m.key);
  if (start == null || !context.mounted) return;
  final (url, headers) = splitHeaders(Session.I.prov!.streamUrl(m));
  await openPlayer(
      context,
      PlayRequest(
          url: url,
          headers: headers,
          title: m.name,
          kind: Kind.movie,
          resumeKey: m.key,
          historyItem: movieHistory(m),
          startAt: start));
}

Future<void> playEpisode(BuildContext context, Episode e, {String showIcon = '', String backdrop = '', int? startAt}) async {
  final start = startAt ?? await askResume(context, e.key);
  if (start == null || !context.mounted) return;
  final (url, headers) = splitHeaders(Session.I.prov!.episodeUrl(e));
  await openPlayer(
      context,
      PlayRequest(
          url: url,
          headers: headers,
          title: '${e.show} ${e.code}',
          subtitle: e.title,
          kind: Kind.series,
          isEpisode: true,
          resumeKey: e.key,
          historyItem: episodeHistory(e, showIcon, backdrop),
          startAt: start));
}

Future<void> resumeFromHistory(BuildContext context, Map<String, dynamic> item, String key, int pos) async {
  if (item['type'] == 'episode') {
    final e = Episode.fromJson(Map<String, dynamic>.from(item['ep'] as Map));
    await playEpisode(context, e, showIcon: toStr(item['icon']), backdrop: toStr(item['backdrop']), startAt: pos);
  } else {
    final m = Item.fromJson(Map<String, dynamic>.from(item['item'] as Map));
    await playMovie(context, m, startAt: pos);
  }
}
