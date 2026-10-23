import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'strings.dart';
import 'theme.dart';

/// Focusable, clickable surface: works with touch, mouse and TV remotes
/// (arrows move the focus, OK / Enter activates). Shows an accent ring when
/// focused.
class Tappable extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocus;
  final bool autofocus;
  final FocusNode? focusNode;
  final double radius;
  final bool ring;
  const Tappable({
    super.key,
    required this.builder,
    this.onTap,
    this.onLongPress,
    this.onFocus,
    this.autofocus = false,
    this.focusNode,
    this.radius = 16,
    this.ring = true,
  });

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.contextMenu): _LongIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap?.call();
          return null;
        }),
        _LongIntent: CallbackAction<_LongIntent>(onInvoke: (_) {
          widget.onLongPress?.call();
          return null;
        }),
      },
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(context,
              alignment: 0.5, duration: const Duration(milliseconds: 150), alignmentPolicy: ScrollPositionAlignmentPolicy.explicit);
        }
        widget.onFocus?.call(f);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: widget.ring && _focused ? C.accent : Colors.transparent, width: 3),
          ),
          child: widget.builder(context, _focused),
        ),
      ),
    );
  }
}

class _LongIntent extends Intent {
  const _LongIntent();
}

/// Network image with a soft placeholder.
class NetImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Widget? placeholder;
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.placeholder});

  @override
  Widget build(BuildContext context) {
    final ph = placeholder ?? const ColoredBox(color: C.card);
    if (url.isEmpty || !url.startsWith('http')) return ph;
    return Image.network(
      url,
      fit: fit,
      cacheWidth: 400,
      errorBuilder: (_, __, ___) => ph,
      loadingBuilder: (c, child, p) => p == null ? child : ph,
    );
  }
}

String initials(String name) {
  final words = name.replaceAll('|', ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty && RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(w[0]));
  final s = words.take(2).map((w) => w[0]).join().toUpperCase();
  return s.isEmpty ? '?' : s;
}

class ChannelLogo extends StatelessWidget {
  final Item ch;
  final double size;
  const ChannelLogo(this.ch, {super.key, this.size = 52});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: C.track, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(4),
      child: NetImage(ch.icon,
          fit: BoxFit.contain,
          placeholder: Center(
              child: Text(initials(ch.name),
                  style: TextStyle(fontWeight: FontWeight.bold, color: C.muted, fontSize: size * 0.3)))),
    );
  }
}

/// Single-line text that scrolls when [active] and too long (marquee).
class Marquee extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final bool active;
  const Marquee(this.text, {super.key, this.style, this.active = true});
  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  bool _running = false;

  @override
  void didUpdateWidget(Marquee old) {
    super.didUpdateWidget(old);
    if (widget.active && !_running) {
      _start();
    } else if (!widget.active && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_running || !mounted || !widget.active) return;
    _running = true;
    while (mounted && widget.active && _scroll.hasClients) {
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) break;
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted || !widget.active || !_scroll.hasClients) break;
      await _scroll.animateTo(max, duration: Duration(milliseconds: (max * 25).toInt()), curve: Curves.linear);
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted || !_scroll.hasClients) break;
      _scroll.jumpTo(0);
    }
    _running = false;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false),
    );
  }
}

class Thin extends StatelessWidget {
  final double value;
  final double height;
  const Thin(this.value, {super.key, this.height = 4});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(value: value.clamp(0.0, 1.0), minHeight: height, color: C.accent, backgroundColor: C.track),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(color: C.accent));
}

class Message extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onRetry;
  const Message(this.text, {super.key, this.icon = Icons.info_outline, this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: C.dim),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, fontSize: 16)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, autofocus: true, child: const Icon(Icons.refresh)),
          ],
        ]),
      ),
    );
  }
}

/// Poster card used by the movie / series grids and the home rows.
class PosterCard extends StatelessWidget {
  final Item item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double progress;
  final bool autofocus;
  final bool isNew;
  const PosterCard(this.item,
      {super.key, required this.onTap, this.onLongPress, this.progress = 0, this.autofocus = false, this.isNew = false});

  @override
  Widget build(BuildContext context) {
    return Tappable(
      autofocus: autofocus,
      onTap: onTap,
      onLongPress: onLongPress,
      radius: 14,
      builder: (context, focused) => AnimatedScale(
        scale: focused ? 1.04 : 1,
        duration: const Duration(milliseconds: 120),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(fit: StackFit.expand, children: [
                NetImage(item.icon,
                    placeholder: Container(
                        color: C.card,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(8),
                        child: Text(item.name,
                            textAlign: TextAlign.center, maxLines: 4, style: const TextStyle(color: C.muted)))),
                if (item.rating > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(8)),
                      child: Text('★ ${item.rating.toStringAsFixed(1)}',
                          style: const TextStyle(color: C.gold, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                if (isNew)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: C.live, borderRadius: BorderRadius.circular(6)),
                      child: const Text('NEW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                if (progress > 0) Positioned(left: 6, right: 6, bottom: 6, child: Thin(progress)),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 20,
            child: Marquee(item.name,
                active: focused, style: TextStyle(fontSize: 14, color: focused ? C.text : C.muted, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, {super.key, this.color = C.teal});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
      );
}

/// Screen header with a back button and a title.
class Header extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const Header(this.title, {super.key, this.actions = const []});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(children: [
        Tappable(
          radius: 14,
          onTap: () => Navigator.of(context).maybePop(),
          builder: (_, f) => Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: f ? C.accent : C.card, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.arrow_back_ios_new, size: 20, color: f ? C.bg : C.text),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
            child: Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
        ...actions,
      ]),
    );
  }
}

class IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? color;
  const IconBtn(this.icon, this.onTap, {super.key, this.tooltip, this.color});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Tooltip(
          message: tooltip ?? '',
          child: Tappable(
            radius: 14,
            onTap: onTap,
            builder: (_, f) => Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: f ? C.accent : C.card, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 22, color: f ? C.bg : (color ?? C.text)),
            ),
          ),
        ),
      );
}

/// Text button that looks like the Kodi skin buttons (accent when focused).
class Btn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool autofocus;
  final bool primary;
  const Btn(this.label, this.onTap, {super.key, this.icon, this.autofocus = false, this.primary = false});
  @override
  Widget build(BuildContext context) => Tappable(
        autofocus: autofocus,
        onTap: onTap,
        radius: 16,
        builder: (_, f) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          decoration: BoxDecoration(
              color: f ? C.accent : (primary ? C.accent.withValues(alpha: 0.85) : C.card), borderRadius: BorderRadius.circular(13)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 20, color: f || primary ? C.bg : C.text), const SizedBox(width: 8)],
            Text(label,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: f || primary ? C.bg : C.text)),
          ]),
        ),
      );
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}

String errorText(Object e) => tf('error', e.toString().replaceFirst('Exception: ', ''));
