import 'dart:isolate';

import 'package:xml/xml_events.dart';

import 'models.dart';
import 'provider.dart' show fold;

final _timeRe = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s*([+-]\d{4})?');

int? parseXmltvTime(String? v) {
  final m = _timeRe.firstMatch((v ?? '').trim());
  if (m == null) return null;
  var ts = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!),
              int.parse(m[6]!))
          .millisecondsSinceEpoch ~/
      1000;
  final tz = m[7];
  if (tz != null) {
    final sign = tz[0] == '-' ? -1 : 1;
    ts -= sign * (int.parse(tz.substring(1, 3)) * 3600 + int.parse(tz.substring(3, 5)) * 60);
  }
  return ts;
}

/// XMLTV -> {channel id (and folded display names): programmes}, keeping
/// yesterday -> +2 days only.
Map<String, List<Programme>> parseXmltv(String text) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final from = now - 7 * 86400; // keep a week for catch-up
  final to = now + 2 * 86400;
  final progs = <String, List<Programme>>{};
  final names = <String, List<String>>{};
  String? curChannel;
  String? curProgChannel;
  int? start, stop;
  String title = '', desc = '';
  String? field;
  final buf = StringBuffer();
  for (final ev in parseEvents(text)) {
    if (ev is XmlStartElementEvent) {
      switch (ev.name) {
        case 'channel':
          curChannel = ev.attributes.where((a) => a.name == 'id').map((a) => a.value).firstOrNull;
          break;
        case 'display-name':
          field = curChannel != null && curProgChannel == null ? 'name' : null;
          buf.clear();
          break;
        case 'programme':
          String attr(String n) => ev.attributes.where((a) => a.name == n).map((a) => a.value).firstOrNull ?? '';
          curProgChannel = attr('channel');
          start = parseXmltvTime(attr('start'));
          stop = parseXmltvTime(attr('stop'));
          title = '';
          desc = '';
          break;
        case 'title':
        case 'desc':
          if (curProgChannel != null) {
            field = ev.name;
            buf.clear();
          }
          break;
      }
      if (ev.isSelfClosing && ev.name == 'channel') curChannel = null;
    } else if (ev is XmlTextEvent || ev is XmlCDATAEvent) {
      if (field != null) buf.write(ev is XmlTextEvent ? ev.value : (ev as XmlCDATAEvent).value);
    } else if (ev is XmlEndElementEvent) {
      switch (ev.name) {
        case 'display-name':
          if (field == 'name' && curChannel != null) names.putIfAbsent(curChannel, () => []).add(fold(buf.toString()));
          field = null;
          break;
        case 'title':
          if (field == 'title' && title.isEmpty) title = buf.toString().trim();
          field = null;
          break;
        case 'desc':
          if (field == 'desc' && desc.isEmpty) desc = buf.toString().trim();
          field = null;
          break;
        case 'channel':
          curChannel = null;
          break;
        case 'programme':
          if (curProgChannel != null && start != null && stop != null && stop > from && start < to) {
            progs.putIfAbsent(curProgChannel, () => []).add(Programme(start, stop, title, desc: desc));
          }
          curProgChannel = null;
          break;
      }
    }
  }
  final out = <String, List<Programme>>{};
  progs.forEach((id, list) {
    list.sort((a, b) => a.start.compareTo(b.start));
    out[id] = list;
    out.putIfAbsent(id.toLowerCase(), () => list);
    for (final n in names[id] ?? const <String>[]) {
      out.putIfAbsent(n, () => list);
    }
  });
  return out;
}

Future<Map<String, List<Programme>>> parseXmltvInBackground(String text) => Isolate.run(() => parseXmltv(text));

Map<String, dynamic> epgToJson(Map<String, List<Programme>> epg) {
  // aliases point to the same list: store each list once
  final ids = <List<Programme>, int>{};
  final lists = <List<List<dynamic>>>[];
  final keys = <String, int>{};
  epg.forEach((k, v) {
    final idx = ids.putIfAbsent(v, () {
      lists.add([for (final p in v) [p.start, p.stop, p.title, p.desc]]);
      return lists.length - 1;
    });
    keys[k] = idx;
  });
  return {'k': keys, 'l': lists};
}

Map<String, List<Programme>> epgFromJson(Map<String, dynamic> j) {
  final lists = [
    for (final l in j['l'] as List)
      [for (final p in l as List) Programme(toInt(p[0]), toInt(p[1]), toStr(p[2]), desc: toStr(p[3]))]
  ];
  return {for (final e in (j['k'] as Map).entries) e.key.toString(): lists[toInt(e.value)]};
}
