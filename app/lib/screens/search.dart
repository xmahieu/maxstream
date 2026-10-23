import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../play.dart';
import '../session.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail.dart';

/// Search across channels, movies and series at once.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Map<Kind, List<Item>> _results = {};
  Timer? _debounce;
  bool _busy = false;

  void _changed(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = {});
      return;
    }
    setState(() => _busy = true);
    final out = <Kind, List<Item>>{};
    for (final k in Kind.values) {
      try {
        out[k] = await Session.I.filter(k, await Session.I.prov!.search(k, q));
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _results = out;
        _busy = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = {Kind.live: t('live'), Kind.movie: t('movies'), Kind.series: t('series')};
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Header(t('search')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              onChanged: _changed,
              onSubmitted: _search,
              decoration: InputDecoration(hintText: t('search_hint'), prefixIcon: const Icon(Icons.search)),
            ),
          ),
          if (_busy) const LinearProgressIndicator(color: C.accent),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              for (final k in Kind.values)
                if ((_results[k] ?? []).isNotEmpty) ...[
                  Text('${labels[k]}  (${_results[k]!.length})', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: k == Kind.live ? 120 : 250,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _results[k]!.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final item = _results[k]![i];
                        if (k == Kind.live) {
                          return SizedBox(
                            width: 150,
                            child: Tappable(
                              radius: 14,
                              onTap: () => playChannel(context, item, zapList: _results[k]!),
                              builder: (_, f) => Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: f ? C.cardFocus : C.card, borderRadius: BorderRadius.circular(11)),
                                child: Column(children: [
                                  ChannelLogo(item, size: 56),
                                  const SizedBox(height: 8),
                                  SizedBox(height: 20, child: Marquee(item.name, active: f)),
                                ]),
                              ),
                            ),
                          );
                        }
                        return SizedBox(
                          width: 145,
                          child: PosterCard(item,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailScreen(item: item)))),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
            ]),
          ),
        ]),
      ),
    );
  }
}
