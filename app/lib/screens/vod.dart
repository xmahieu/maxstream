import 'package:flutter/material.dart';

import '../models.dart';
import '../session.dart';
import '../store.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail.dart';

const _all = '__all', _fav = '__fav';

class VodScreen extends StatefulWidget {
  final Kind kind;
  const VodScreen({super.key, required this.kind});
  @override
  State<VodScreen> createState() => _VodScreenState();
}

class _VodScreenState extends State<VodScreen> {
  List<Item> _all0 = [];
  List<Category> _cats = [];
  Map<String, int> _counts = {};
  String _cat = _all;
  List<Item> _items = [];
  int _sort = 0; // 0 added, 1 name, 2 rating
  String _query = '';
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = Session.I;
      final all = await s.filter(widget.kind, await s.prov!.allItems(widget.kind));
      final cats = await s.categories(widget.kind);
      final counts = <String, int>{};
      for (final i in all) {
        counts[i.cat] = (counts[i.cat] ?? 0) + 1;
      }
      setState(() {
        _all0 = all;
        _cats = cats.where((c) => (counts[c.id] ?? 0) > 0).toList();
        _counts = counts;
        _loading = false;
      });
      _apply();
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _apply([String? cat]) {
    cat ??= _cat;
    List<Item> list;
    if (cat == _all) {
      list = List.of(_all0);
    } else if (cat == _fav) {
      list = Store.favourites(Session.I.pl!.id, widget.kind);
    } else {
      list = _all0.where((i) => i.cat == cat).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((i) => i.name.toLowerCase().contains(q)).toList();
    }
    switch (_sort) {
      case 0:
        list.sort((a, b) => b.added.compareTo(a.added));
        break;
      case 1:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 2:
        list.sort((a, b) => b.rating.compareTo(a.rating));
        break;
    }
    setState(() {
      _cat = cat!;
      _items = list;
    });
  }

  Future<void> _openItem(Item item) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailScreen(item: item, siblings: _items.take(40).toList())));
    if (_cat == _fav) _apply();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.kind == Kind.movie ? t('movies') : t('series');
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          return Column(children: [
            Header(title, actions: [
              if (wide)
                for (final (i, label) in [t('sort_added'), t('sort_name'), t('sort_rating')].indexed)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Tappable(
                      radius: 14,
                      onTap: () {
                        _sort = i;
                        _apply();
                      },
                      builder: (_, f) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                            color: _sort == i ? C.accent : (f ? C.cardFocus : C.card), borderRadius: BorderRadius.circular(11)),
                        child: Text(label, style: TextStyle(color: _sort == i ? C.bg : C.text, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
              const SizedBox(width: 8),
              SizedBox(
                width: wide ? 300 : 170,
                child: TextField(
                  decoration: InputDecoration(hintText: t('search_hint'), prefixIcon: const Icon(Icons.search), isDense: true),
                  onChanged: (v) {
                    _query = v.trim();
                    _apply();
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
                          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Padding(padding: const EdgeInsets.fromLTRB(12, 4, 0, 12), child: _catColumn()),
                              Expanded(child: _grid(wide)),
                            ])
                          : Column(children: [_catChips(), Expanded(child: _grid(wide))]),
            ),
          ]);
        }),
      ),
    );
  }

  List<(String, String, int)> _entries() => [
        (_all, t('all'), _all0.length),
        (_fav, t('favourites'), Store.favourites(Session.I.pl!.id, widget.kind).length),
        for (final c in _cats) (c.id, c.name, _counts[c.id] ?? 0),
      ];

  Widget _catColumn() {
    final cats = _entries();
    return Container(
      width: 290,
      decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(20)),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: cats.length,
        itemBuilder: (_, i) {
          final c = cats[i];
          final sel = c.$1 == _cat;
          return Tappable(
            autofocus: i == 0,
            radius: 14,
            onTap: () => _apply(c.$1),
            onFocus: (f) {
              if (f) _apply(c.$1);
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
    );
  }

  Widget _catChips() {
    final cats = _entries();
    return SizedBox(
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
            onTap: () => _apply(c.$1),
            builder: (_, f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: sel ? C.sel : C.card, borderRadius: BorderRadius.circular(18)),
              child: Text('${c.$2}  ${c.$3}', style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
            ),
          );
        },
      ),
    );
  }

  Widget _grid(bool wide) {
    if (_items.isEmpty) return Message(t('no_items'));
    final pid = Session.I.pl!.id;
    final weekAgo = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 7 * 86400;
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: wide ? 190 : 130,
        childAspectRatio: 0.58,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        final r = widget.kind == Kind.movie ? Store.resumeOf(pid, item.key) : null;
        final progress = r == null || toInt(r['total']) == 0 ? 0.0 : toInt(r['pos']) / toInt(r['total']);
        return PosterCard(
          item,
          onTap: () => _openItem(item),
          onLongPress: () async {
            await Store.toggleFavourite(pid, item);
            if (!mounted) return;
            toast(context, Store.isFavourite(pid, item.key) ? t('fav_add') : t('fav_remove'));
            if (_cat == _fav) _apply();
          },
          progress: progress,
          isNew: item.added > weekAgo && Session.I.pl!.isXtream,
        );
      },
    );
  }
}
