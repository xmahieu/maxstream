import 'package:flutter/material.dart';

import '../models.dart';
import '../play.dart';
import '../session.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';

/// Programme listing of one channel by day; past programmes with an
/// archive play as catch-up, the current one plays live.
class GuideScreen extends StatefulWidget {
  final Item channel;
  final List<Item> zapList;
  const GuideScreen({super.key, required this.channel, this.zapList = const []});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  List<Programme>? _progs;
  Object? _error;
  late DateTime _day;
  final List<DateTime> _days = [];

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _day = DateTime(today.year, today.month, today.day);
    final back = widget.channel.catchup ? (widget.channel.catchupDays > 0 ? widget.channel.catchupDays : 7).clamp(1, 14) : 0;
    for (var i = -back; i <= 1; i++) {
      _days.add(_day.add(Duration(days: i)));
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Session.I.prov!.channelProgrammes(widget.channel);
      setState(() => _progs = p);
    } catch (e) {
      setState(() => _error = e);
    }
  }

  String _dayLabel(DateTime d) {
    final n = DateTime.now();
    final diff = (d.difference(DateTime(n.year, n.month, n.day)).inHours / 24).round();
    if (diff == 0) return t('today');
    if (diff == -1) return t('yesterday');
    if (diff == 1) return t('tomorrow');
    const fr = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final names = t('today') == 'Today' ? en : fr;
    return '${names[d.weekday - 1]} ${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    final start = _day.millisecondsSinceEpoch ~/ 1000;
    final end = start + 86400;
    final now = Session.I.nowSec;
    final list = (_progs ?? []).where((p) => p.stop > start && p.start < end).toList();
    final nowIdx = list.indexWhere((p) => p.isNow(now));
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Header('${t('guide')} · ${widget.channel.name}'),
          SizedBox(
            height: 56,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final d = _days[i];
                final sel = d == _day;
                return Tappable(
                  radius: 20,
                  onTap: () => setState(() => _day = d),
                  builder: (_, f) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: sel ? C.accent : C.card, borderRadius: BorderRadius.circular(18)),
                    child: Text(_dayLabel(d), style: TextStyle(color: sel ? C.bg : C.text, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _progs == null && _error == null
                ? const Loading()
                : _error != null
                    ? Message(errorText(_error!))
                    : list.isEmpty
                        ? Message(t('no_epg'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final p = list[i];
                              final isNow = p.isNow(now);
                              final past = p.stop <= now;
                              final playable = isNow || (past && p.archive);
                              return Tappable(
                                autofocus: i == (nowIdx < 0 ? 0 : nowIdx),
                                radius: 14,
                                onTap: () {
                                  if (isNow) {
                                    playChannel(context, widget.channel, zapList: widget.zapList);
                                  } else if (past && p.archive) {
                                    playCatchup(context, widget.channel, p);
                                  } else if (!widget.channel.catchup) {
                                    toast(context, t('no_catchup'));
                                  }
                                },
                                builder: (_, f) => Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                      color: f ? C.cardFocus : (isNow ? C.sel : C.panel), borderRadius: BorderRadius.circular(11)),
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    SizedBox(
                                      width: 120,
                                      child: Text('${fmtClock(p.start)} - ${fmtClock(p.stop)}',
                                          style: TextStyle(color: playable ? C.text : C.dim, fontWeight: FontWeight.bold)),
                                    ),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Row(children: [
                                          Expanded(
                                              child: Text(p.title,
                                                  style: TextStyle(
                                                      fontSize: 17, fontWeight: FontWeight.bold, color: playable ? C.text : C.dim))),
                                          if (isNow) Pill(t('live_now'), color: C.live),
                                          if (past && p.archive) Pill(t('replay')),
                                        ]),
                                        if (f && p.desc.isNotEmpty)
                                          Padding(
                                              padding: const EdgeInsets.only(top: 6),
                                              child: Text(p.desc, style: const TextStyle(color: C.muted))),
                                        if (isNow) Padding(padding: const EdgeInsets.only(top: 8), child: Thin(p.progress(now))),
                                      ]),
                                    ),
                                  ]),
                                ),
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }
}
