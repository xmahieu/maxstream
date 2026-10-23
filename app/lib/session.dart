import 'package:flutter/foundation.dart';

import 'models.dart';
import 'provider.dart';
import 'store.dart';

const defaultAdultWords = ['adult', 'xxx', '18+', '+18', 'porn', 'for adults', 'adultes'];

/// Active playlist + provider shared by every screen, and an on-demand EPG
/// cache (now / next) for the channels shown on screen.
class Session extends ChangeNotifier {
  static final Session I = Session._();
  Session._();

  Playlist? pl;
  Provider? prov;
  bool unlocked = false;

  void load() {
    pl = Store.activePlaylist();
    prov = pl == null ? null : providerFor(pl!);
    _epg.clear();
    _pending.clear();
    notifyListeners();
  }

  void activate(Playlist p) {
    Store.activeId = p.id;
    load();
  }

  // ------------------------------------------------------------ parental
  bool get parentalOn => Store.getBool('parental', false) && !unlocked;

  bool isAdult(String name) {
    final n = name.toLowerCase();
    return defaultAdultWords.any(n.contains);
  }

  Future<List<Category>> categories(Kind kind) async {
    final cats = await prov!.categories(kind);
    return parentalOn ? cats.where((c) => !isAdult(c.name)).toList() : cats;
  }

  Future<List<Item>> filter(Kind kind, List<Item> items) async {
    if (!parentalOn) return items;
    final adult = {for (final c in await prov!.categories(kind)) if (isAdult(c.name)) c.id};
    return adult.isEmpty ? items : items.where((i) => !adult.contains(i.cat)).toList();
  }

  // ------------------------------------------------------------ EPG now/next
  final Map<String, List<Programme>> _epg = {};
  final Set<String> _pending = {};
  int _running = 0;
  final List<Item> _queue = [];

  List<Programme>? epgFor(Item ch) => _epg[ch.id];

  /// Ask for a channel's programmes; listeners are notified when they arrive.
  void requestEpg(Item ch) {
    if (_epg.containsKey(ch.id) || _pending.contains(ch.id) || prov == null) return;
    _pending.add(ch.id);
    _queue.add(ch);
    _pump();
  }

  void _pump() {
    while (_running < 4 && _queue.isNotEmpty) {
      final ch = _queue.removeLast(); // most recently shown first
      _running++;
      prov!.shortEpg(ch).then((progs) {
        _epg[ch.id] = progs;
      }).catchError((_) {
        _epg[ch.id] = const [];
      }).whenComplete(() {
        _running--;
        _pending.remove(ch.id);
        notifyListeners();
        _pump();
      });
    }
  }

  void forgetQueuedEpg() {
    for (final ch in _queue) {
      _pending.remove(ch.id);
    }
    _queue.clear();
  }

  int get nowSec => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
