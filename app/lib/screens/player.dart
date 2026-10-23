import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../languages.dart';
import '../models.dart';
import '../net.dart';
import '../play.dart';
import '../session.dart';
import '../store.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';

/// mpv options shared by the full-screen player and the live preview:
/// a large cache and automatic reconnection when the provider stalls.
Future<void> configurePlayer(Player player, Map<String, String> headers) async {
  final native = player.platform;
  if (native is! NativePlayer) return;
  final ua = headers['User-Agent'] ?? headers['user-agent'] ?? defaultUserAgent;
  final extra = headers.entries.where((e) => e.key.toLowerCase() != 'user-agent').map((e) => '${e.key}: ${e.value}').join(',');
  final props = <String, String>{
    'user-agent': ua,
    'network-timeout': '20',
    'stream-lavf-o': 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5',
    'cache': 'yes',
    'cache-secs': '60',
    'demuxer-max-bytes': '150MiB',
    'demuxer-max-back-bytes': '50MiB',
    'demuxer-readahead-secs': '30',
    if (extra.isNotEmpty) 'http-header-fields': extra,
  };
  for (final e in props.entries) {
    try {
      await native.setProperty(e.key, e.value);
    } catch (_) {}
  }
}

/// Applies the preferred audio / subtitle languages once the tracks are known.
void applyLanguagePrefs(Player player, Tracks tracks) {
  final audioPref = Store.getInt('audio_language', 0);
  final subMode = Store.getInt('subtitle_mode', subKodi);
  final subLang = Store.getInt('subtitle_language', 1);
  if (audioPref == 0 && subMode == subKodi) return;
  final audios = tracks.audio.where((a) => a.id != 'auto' && a.id != 'no').toList();
  final subs = tracks.subtitle.where((s) => s.id != 'auto' && s.id != 'no').toList();
  AudioTrack current = player.state.track.audio;
  if (audioPref != 0 && audios.isNotEmpty) {
    final i = pickTrack([for (final a in audios) (a.language, a.title, false)], audioPref);
    if (i != null) {
      player.setAudioTrack(audios[i]);
      current = audios[i];
    }
  }
  if (subMode == subKodi) return;
  final tuples = [for (final s in subs) (s.language, s.title, (s.title ?? '').toLowerCase().contains('forc'))];
  int? target;
  if (subMode == subAlways) {
    target = pickTrack(tuples, subLang);
  } else if (subMode == subForeign) {
    if (!langMatches(current.language, current.title, subLang)) {
      target = pickTrack(tuples, subLang, forced: false) ?? pickTrack(tuples, subLang);
    }
  } else if (subMode == subForced) {
    target = pickTrack(tuples, subLang, forced: true);
  }
  player.setSubtitleTrack(target == null ? SubtitleTrack.no() : subs[target]);
}

class PlayerScreen extends StatefulWidget {
  final PlayRequest request;
  final List<Item> zapList;
  final Item? channel;
  const PlayerScreen({super.key, required this.request, this.zapList = const [], this.channel});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player(configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024, title: 'MaxStream'));
  late final VideoController _video = VideoController(_player);
  final List<StreamSubscription> _subs = [];
  final FocusNode _root = FocusNode();
  final FocusNode _playBtn = FocusNode();

  late PlayRequest _req = widget.request;
  Item? _channel;
  bool _overlay = true;
  Timer? _hide;
  Timer? _saveTimer;
  bool _seekedToStart = false;
  bool _langApplied = false;
  String? _status; // reconnecting / error text
  final List<DateTime> _retries = [];
  Duration _pos = Duration.zero, _dur = Duration.zero;
  bool _playing = false, _buffering = true;
  String _zapDigits = '';
  Timer? _zapTimer;

  bool get _live => _req.kind == Kind.live && !_req.isCatchup;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    _subs.addAll([
      _player.stream.position.listen((p) => _pos = p),
      _player.stream.duration.listen((d) {
        _dur = d;
        if (!_seekedToStart && _req.startAt > 0 && d > Duration.zero) {
          _seekedToStart = true;
          _player.seek(Duration(seconds: _req.startAt));
        }
      }),
      _player.stream.playing.listen((v) => setState(() => _playing = v)),
      _player.stream.buffering.listen((v) => setState(() => _buffering = v)),
      _player.stream.tracks.listen((tr) {
        if (!_langApplied && (tr.audio.length > 2 || tr.subtitle.length > 2)) {
          _langApplied = true;
          applyLanguagePrefs(_player, tr);
        }
      }),
      _player.stream.error.listen(_onError),
      _player.stream.completed.listen((done) {
        if (done && _live) _retry('end of stream');
      }),
    ]);
    _open();
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveResume());
    _showOverlay();
  }

  Future<void> _open() async {
    _seekedToStart = false;
    _langApplied = false;
    await configurePlayer(_player, _req.headers);
    await _player.open(Media(_req.url, httpHeaders: _req.headers));
  }

  void _onError(String err) {
    final e = err.toLowerCase();
    if (e.contains('401') || e.contains('403') || e.contains('forbidden') || e.contains('unauthorized')) {
      setState(() => _status = t('refused'));
      return;
    }
    if (_live) {
      _retry(err);
    } else {
      setState(() => _status = tf('stream_error', err));
    }
  }

  /// Live channels: re-open after a drop, never more than 6 times a minute
  /// (providers ban accounts that reconnect in a loop).
  void _retry(String reason) {
    final now = DateTime.now();
    _retries.removeWhere((d) => now.difference(d) > const Duration(minutes: 1));
    if (_retries.length >= 6) {
      setState(() => _status = tf('stream_error', reason));
      return;
    }
    _retries.add(now);
    setState(() => _status = t('reconnecting'));
    Future.delayed(Duration(milliseconds: 500 * _retries.length), () async {
      if (!mounted) return;
      await _player.open(Media(_req.url, httpHeaders: _req.headers));
      if (mounted) setState(() => _status = null);
    });
  }

  void _saveResume() {
    final pl = Session.I.pl;
    if (pl == null || _req.resumeKey.isEmpty || _dur.inSeconds <= 0 || _pos.inSeconds < 5) return;
    Store.saveResume(pl.id, _req.resumeKey, _pos.inSeconds, _dur.inSeconds, _req.historyItem);
  }

  @override
  void dispose() {
    _saveResume();
    _hide?.cancel();
    _saveTimer?.cancel();
    _zapTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _root.dispose();
    _playBtn.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ overlay
  void _showOverlay() {
    setState(() => _overlay = true);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _overlay = false);
        _root.requestFocus();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlay && !_playBtn.hasFocus && FocusManager.instance.primaryFocus == _root) _playBtn.requestFocus();
    });
  }

  void _seekBy(int seconds) {
    if (_live) return;
    var target = _pos + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_dur > Duration.zero && target > _dur) target = _dur - const Duration(seconds: 2);
    _player.seek(target);
    _showOverlay();
  }

  Future<void> _zap(int delta) async {
    final list = widget.zapList;
    if (!_live || list.isEmpty || _channel == null) return;
    var idx = list.indexWhere((c) => c.id == _channel!.id);
    idx = (idx + delta) % list.length;
    if (idx < 0) idx += list.length;
    await _switchTo(list[idx]);
  }

  Future<void> _switchTo(Item ch) async {
    _channel = ch;
    _req = channelRequest(ch);
    _retries.clear();
    setState(() => _status = null);
    _showOverlay();
    await Store.addRecentChannel(Session.I.pl!.id, ch);
    await _player.stop();
    await _open();
  }

  void _digit(int d) {
    if (!_live || widget.zapList.isEmpty) return;
    _zapDigits += '$d';
    setState(() {});
    _zapTimer?.cancel();
    _zapTimer = Timer(const Duration(milliseconds: 1500), () {
      final n = int.tryParse(_zapDigits) ?? 0;
      _zapDigits = '';
      final ch = widget.zapList.where((c) => c.num == n).firstOrNull;
      if (ch != null) _switchTo(ch);
      if (mounted) setState(() {});
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent ev) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = ev.logicalKey;
    if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.space) {
      _player.playOrPause();
      _showOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(30);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-30);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.channelUp || k == LogicalKeyboardKey.pageUp) {
      _zap(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.channelDown || k == LogicalKeyboardKey.pageDown) {
      _zap(1);
      return KeyEventResult.handled;
    }
    final digit = int.tryParse(ev.character ?? '');
    if (digit != null && ev is KeyDownEvent) {
      _digit(digit);
      return KeyEventResult.handled;
    }
    if (_overlay) {
      _showOverlay(); // any key keeps the controls visible
      return KeyEventResult.ignored; // arrows move between buttons
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _seekBy(10);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _live ? _zap(-1) : _showOverlay();
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _live ? _zap(1) : _showOverlay();
    } else if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _showOverlay();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ------------------------------------------------------------ track menus
  Future<void> _chooseAudio() async {
    final tracks = _player.state.tracks.audio.where((a) => a.id != 'no').toList();
    final cur = _player.state.track.audio;
    final pick = await _menu<AudioTrack>(t('audio'), [
      for (final a in tracks) (a, a.id == 'auto' ? t('auto') : _trackLabel(a.title, a.language, a.id), a.id == cur.id),
    ]);
    if (pick != null) _player.setAudioTrack(pick);
  }

  Future<void> _chooseSubs() async {
    final tracks = _player.state.tracks.subtitle.where((s) => s.id != 'auto').toList();
    final cur = _player.state.track.subtitle;
    final pick = await _menu<SubtitleTrack>(t('subtitles'), [
      for (final s in tracks) (s, s.id == 'no' ? t('off') : _trackLabel(s.title, s.language, s.id), s.id == cur.id),
    ]);
    if (pick != null) _player.setSubtitleTrack(pick);
  }

  String _trackLabel(String? title, String? lang, String id) {
    final parts = [if ((lang ?? '').isNotEmpty) lang!.toUpperCase(), if ((title ?? '').isNotEmpty) title!];
    return parts.isEmpty ? '#$id' : parts.join(' · ');
  }

  Future<T?> _menu<T>(String title, List<(T, String, bool)> options) {
    _hide?.cancel();
    return showDialog<T>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(title),
        children: [
          for (final o in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, o.$1),
              child: Row(children: [
                Icon(o.$3 ? Icons.radio_button_checked : Icons.radio_button_off, color: o.$3 ? C.accent : C.dim),
                const SizedBox(width: 12),
                Expanded(child: Text(o.$2, style: const TextStyle(fontSize: 17))),
              ]),
            ),
        ],
      ),
    ).whenComplete(_showOverlay);
  }

  // ------------------------------------------------------------ view
  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_overlay,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _hide?.cancel();
          setState(() => _overlay = false);
          _root.requestFocus();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _root,
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _overlay ? setState(() => _overlay = false) : _showOverlay(),
            onDoubleTap: _live ? null : () => _player.playOrPause(),
            child: Stack(fit: StackFit.expand, children: [
              Video(controller: _video, controls: NoVideoControls, fill: Colors.black),
              if (_buffering && _status == null) const Center(child: CircularProgressIndicator(color: C.accent)),
              if (_status != null)
                Center(
                  child: Container(
                    margin: const EdgeInsets.all(30),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16)),
                    child: Text(_status!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
                  ),
                ),
              if (_zapDigits.isNotEmpty)
                Positioned(
                  top: 30,
                  right: 40,
                  child: Text(_zapDigits, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: C.accent)),
                ),
              AnimatedOpacity(
                opacity: _overlay ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(ignoring: !_overlay, child: ExcludeFocus(excluding: !_overlay, child: _controls())),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    final title = _live && _channel != null ? _channel!.name : _req.title;
    final epg = _live && _channel != null ? Session.I.epgFor(_channel!) : null;
    final now = Session.I.nowSec;
    final cur = epg?.where((p) => p.isNow(now)).firstOrNull;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent, Colors.transparent, Color(0xDD000000)],
          stops: [0, 0.25, 0.6, 1],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBtn(Icons.arrow_back_ios_new, () => Navigator.of(context).pop()),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              if (_req.subtitle.isNotEmpty || cur != null)
                Text(cur != null ? '${fmtClock(cur.start)} - ${fmtClock(cur.stop)}  ${cur.title}' : _req.subtitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 16)),
            ]),
          ),
          if (_live) const Pill('LIVE', color: C.live),
        ]),
        const Spacer(),
        if (!_live)
          Row(children: [
            Text(_fmt(_pos), style: const TextStyle(fontSize: 15)),
            Expanded(
              child: Slider(
                value: _dur.inMilliseconds <= 0 ? 0 : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0),
                onChanged: _dur.inMilliseconds <= 0
                    ? null
                    : (v) => _player.seek(Duration(milliseconds: (v * _dur.inMilliseconds).toInt())),
                activeColor: C.accent,
                inactiveColor: C.track,
              ),
            ),
            Text(_fmt(_dur), style: const TextStyle(fontSize: 15)),
          ]),
        if (cur != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Thin(cur.progress(now))),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (_live && widget.zapList.length > 1) IconBtn(Icons.skip_previous_rounded, () => _zap(-1)),
          if (!_live) IconBtn(Icons.replay_10_rounded, () => _seekBy(-10)),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Tappable(
              focusNode: _playBtn,
              radius: 40,
              onTap: () {
                _player.playOrPause();
                _showOverlay();
              },
              builder: (_, f) => Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: f ? C.accent : C.card, shape: BoxShape.circle),
                child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 38, color: f ? C.bg : C.text),
              ),
            ),
          ),
          if (!_live) IconBtn(Icons.forward_10_rounded, () => _seekBy(10)),
          if (_live && widget.zapList.length > 1) IconBtn(Icons.skip_next_rounded, () => _zap(1)),
          const SizedBox(width: 24),
          IconBtn(Icons.audiotrack_rounded, _chooseAudio, tooltip: t('audio')),
          IconBtn(Icons.subtitles_rounded, _chooseSubs, tooltip: t('subtitles')),
        ]),
      ]),
    );
  }
}
