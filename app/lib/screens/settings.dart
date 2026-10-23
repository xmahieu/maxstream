import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../languages.dart';
import '../session.dart';
import '../store.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';

const donateUrl = 'https://paypal.me/MaxStreamKodi/5EUR';

/// A settings row: label + current value, opens a choice list.
class _Choice extends StatelessWidget {
  final String label;
  final String settingKey;
  final int def;
  final Map<int, String> options;
  final VoidCallback onChanged;
  final bool autofocus;
  const _Choice(this.label, this.settingKey, this.def, this.options, this.onChanged, {this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final value = Store.getInt(settingKey, def);
    return _Row(
      label: label,
      value: options[value] ?? '',
      autofocus: autofocus,
      onTap: () async {
        final pick = await showDialog<int>(
          context: context,
          builder: (c) => SimpleDialog(title: Text(label), children: [
            for (final e in options.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, e.key),
                child: Row(children: [
                  Icon(e.key == value ? Icons.radio_button_checked : Icons.radio_button_off, color: e.key == value ? C.accent : C.dim),
                  const SizedBox(width: 12),
                  Expanded(child: Text(e.value, style: const TextStyle(fontSize: 17))),
                ]),
              ),
          ]),
        );
        if (pick != null) {
          await Store.setInt(settingKey, pick);
          onChanged();
        }
      },
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool autofocus;
  final IconData? icon;
  const _Row({required this.label, this.value = '', required this.onTap, this.autofocus = false, this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Tappable(
          autofocus: autofocus,
          radius: 14,
          onTap: onTap,
          builder: (_, f) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(color: f ? C.cardFocus : C.card, borderRadius: BorderRadius.circular(11)),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, color: C.accent), const SizedBox(width: 12)],
              Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
              Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(color: C.muted, fontSize: 16))),
            ]),
          ),
        ),
      );
}

Widget _section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Text(title, style: const TextStyle(fontSize: 15, color: C.accent, fontWeight: FontWeight.bold)),
    );

Future<String?> askPin(BuildContext context, String title) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: true,
        maxLength: 4,
        keyboardType: TextInputType.number,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
      ],
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _changed() => setState(() {});

  Future<void> _toggleParental() async {
    final on = Store.getBool('parental', false);
    if (!on) {
      final pin = await askPin(context, t('pin_set'));
      if (pin == null || pin.length != 4) return;
      await Store.setString('pin', pin);
      await Store.setBool('parental', true);
      Session.I.unlocked = false;
    } else {
      final pin = await askPin(context, t('pin_enter'));
      if (pin == null) return;
      if (pin != Store.getString('pin', '')) {
        if (mounted) toast(context, t('pin_wrong'));
        return;
      }
      await Store.setBool('parental', false);
    }
    Session.I.load();
    _changed();
  }

  Future<void> _unlock() async {
    final pin = await askPin(context, t('pin_enter'));
    if (pin == null) return;
    if (pin == Store.getString('pin', '')) {
      Session.I.unlocked = true;
      Session.I.load();
    } else if (mounted) {
      toast(context, t('pin_wrong'));
    }
    _changed();
  }

  Future<void> _refresh() async {
    final prov = Session.I.prov;
    if (prov == null) return;
    await prov.refresh();
    Session.I.load();
    if (mounted) toast(context, t('refreshed'));
  }

  @override
  Widget build(BuildContext context) {
    final langNames = {0: t('player_default'), for (final e in langs.entries) e.key: e.value.label};
    final subLangs = {for (final e in langs.entries) e.key: e.value.label};
    final parental = Store.getBool('parental', false);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Header(t('settings')),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  _section(t('lang_section')),
                  _Choice(t('audio_lang'), 'audio_language', 0, langNames, _changed, autofocus: true),
                  _Choice(t('sub_mode'), 'subtitle_mode', subKodi, {
                    subKodi: t('player_default'),
                    subOff: t('off'),
                    subAlways: t('sub_always'),
                    subForeign: t('sub_foreign'),
                    subForced: t('sub_forced'),
                  }, _changed),
                  _Choice(t('sub_lang'), 'subtitle_language', 1, subLangs, _changed),
                  _section(t('playback')),
                  _Choice(t('live_format'), 'live_format', 0, const {0: 'MPEG-TS (.ts)', 1: 'HLS (.m3u8)'}, _changed),
                  _Row(label: t('refresh'), icon: Icons.refresh, onTap: _refresh),
                  _section(t('parental')),
                  _Row(label: t('parental_on'), value: parental ? '✓' : '—', onTap: _toggleParental, icon: Icons.lock_outline),
                  if (parental && !Session.I.unlocked) _Row(label: t('unlock'), onTap: _unlock, icon: Icons.lock_open),
                  _section(t('about')),
                  _Row(
                      label: t('donate'),
                      icon: Icons.star_rounded,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DonateScreen()))),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('MaxStream 1.0 · ${t('disclaimer')}', style: const TextStyle(color: C.dim)),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class DonateScreen extends StatelessWidget {
  const DonateScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Header(t('donate')),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded, size: 72, color: C.star),
                    const SizedBox(height: 16),
                    Text(t('donate_text'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, height: 1.4)),
                    const SizedBox(height: 10),
                    const SelectableText('paypal.me/MaxStreamKodi/5EUR', style: TextStyle(color: C.accent, fontSize: 18)),
                    const SizedBox(height: 24),
                    Btn(t('open_paypal'), () => launchUrl(Uri.parse(donateUrl), mode: LaunchMode.externalApplication),
                        icon: Icons.open_in_new, autofocus: true, primary: true),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Map<String, String>? _info;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Session.I.prov!.accountInfo().then((v) => setState(() {
          _info = v;
          _loading = false;
        }), onError: (Object e) => setState(() {
          _error = e;
          _loading = false;
        }));
  }

  @override
  Widget build(BuildContext context) {
    final pl = Session.I.pl!;
    final rows = <(String, String)>[
      (t('name'), pl.name),
      if (_info != null) ...[
        (t('username'), _info!['username'] ?? ''),
        (t('account_status'), _info!['status'] ?? ''),
        (t('account_exp'), _info!['exp'] ?? ''),
        (t('account_cons'), _info!['connections'] ?? ''),
        (t('account_created'), _info!['created'] ?? ''),
        ('Server', _info!['server'] ?? ''),
      ] else if (!pl.isXtream)
        (t('m3u_url'), pl.m3uUrl),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Header(t('account')),
          Expanded(
            child: _loading
                ? const Loading()
                : ListView(padding: const EdgeInsets.all(20), children: [
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          SizedBox(width: 180, child: Text(r.$1, style: const TextStyle(color: C.muted, fontSize: 17))),
                          Expanded(child: SelectableText(r.$2, style: const TextStyle(fontSize: 17))),
                        ]),
                      ),
                    if (_error != null) Text(errorText(_error!), style: const TextStyle(color: C.live)),
                  ]),
          ),
        ]),
      ),
    );
  }
}
