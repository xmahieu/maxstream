import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../licence.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';

/// Shown when the free week is over (and from the "buy" button during the
/// trial): device code, PayPal button and a QR code for TVs without browser.
class LicenceScreen extends StatefulWidget {
  final bool canClose;
  const LicenceScreen({super.key, this.canClose = false});
  @override
  State<LicenceScreen> createState() => _LicenceScreenState();
}

class _LicenceScreenState extends State<LicenceScreen> {
  Timer? _poll;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    Licence.I.addListener(_changed);
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => Licence.I.check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    Licence.I.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (Licence.I.status == LicenceStatus.paid && widget.canClose) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final s = await Licence.I.check();
    if (!mounted) return;
    setState(() => _checking = false);
    if (s != LicenceStatus.paid) toast(context, t('lic_not_yet'));
  }

  @override
  Widget build(BuildContext context) {
    final l = Licence.I;
    final paid = l.status == LicenceStatus.paid;
    final title = paid
        ? t('lic_paid')
        : l.status == LicenceStatus.trial
            ? tf('lic_trial_left', l.daysLeft)
            : t('lic_expired');
    final body = SafeArea(
      child: Column(children: [
        if (widget.canClose) Header(t('lic_title')),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: LayoutBuilder(builder: (context, box) {
                  final wide = box.maxWidth > 640;
                  final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/icon.png', width: 52)),
                      const SizedBox(width: 14),
                      Expanded(child: Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
                    ]),
                    const SizedBox(height: 16),
                    if (!paid)
                      Text(tf('lic_offer', l.price.replaceAll('.00', '')),
                          style: const TextStyle(fontSize: 18, height: 1.45, color: Color(0xFFD2DCEB))),
                    const SizedBox(height: 18),
                    Text(t('lic_device'), style: const TextStyle(color: C.muted)),
                    const SizedBox(height: 4),
                    SelectableText(l.device,
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: C.accent, letterSpacing: 2)),
                    const SizedBox(height: 22),
                    if (!paid)
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        Btn(tf('lic_pay', l.price.replaceAll('.00', '')),
                            () => launchUrl(Uri.parse(l.payUrl), mode: LaunchMode.externalApplication),
                            icon: Icons.lock_open_rounded, autofocus: true, primary: true),
                        Btn(_checking ? t('checking') : t('lic_check'), _check, icon: Icons.refresh),
                      ]),
                    const SizedBox(height: 16),
                    Text(t('lic_help'), style: const TextStyle(color: C.dim, fontSize: 14)),
                  ]);
                  final qr = Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                    child: QrImageView(data: l.payUrl, size: wide ? 230 : 190, backgroundColor: Colors.white),
                  );
                  final qrBlock = Column(children: [
                    qr,
                    const SizedBox(height: 8),
                    Text(t('lic_scan'), textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
                  ]);
                  if (paid) return text;
                  return wide
                      ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          Expanded(child: text),
                          const SizedBox(width: 36),
                          SizedBox(width: 260, child: qrBlock),
                        ])
                      : Column(children: [text, const SizedBox(height: 24), qrBlock]);
                }),
              ),
            ),
          ),
        ),
      ]),
    );
    return Scaffold(body: body);
  }
}

/// Puts the lock screen in front of the app when the trial is over.
class LicenceGate extends StatefulWidget {
  final Widget child;
  const LicenceGate({super.key, required this.child});
  @override
  State<LicenceGate> createState() => _LicenceGateState();
}

class _LicenceGateState extends State<LicenceGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    Licence.I.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    Licence.I.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Licence.I.check();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Licence.I.locked ? const LicenceScreen() : widget.child;
}
