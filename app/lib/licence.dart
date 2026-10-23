import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:http/http.dart' as http;

import 'store.dart';

/// Licence server (Cloudflare Worker). Empty = licensing disabled.
const licenceServer = String.fromEnvironment('LICENCE_URL', defaultValue: '');
const trialDays = 7;

enum LicenceStatus { checking, trial, paid, expired }

/// 7 days free per device, then a lifetime licence per device.
class Licence extends ChangeNotifier {
  static final Licence I = Licence._();
  Licence._();

  LicenceStatus status = LicenceStatus.checking;
  String device = '';
  int trialEnds = 0;
  String price = '15.00';
  Timer? _timer;

  bool get enabled => licenceServer.isNotEmpty;
  bool get locked => enabled && status == LicenceStatus.expired;
  int get daysLeft {
    final left = trialEnds - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return left <= 0 ? 0 : (left / 86400).ceil();
  }

  String get payUrl => '$licenceServer/pay?d=${Uri.encodeComponent(device)}';

  Future<void> init() async {
    device = await deviceCode();
    if (!enabled) {
      status = LicenceStatus.paid;
      return;
    }
    _fromCache();
    unawaited(check());
    _timer = Timer.periodic(const Duration(hours: 6), (_) => check());
  }

  void _apply(Map<String, dynamic> j) {
    final s = j['status'];
    trialEnds = (j['trial_ends'] as num?)?.toInt() ?? trialEnds;
    price = (j['price'] ?? price).toString();
    status = s == 'paid'
        ? LicenceStatus.paid
        : s == 'trial'
            ? LicenceStatus.trial
            : LicenceStatus.expired;
    // the server answered "trial" earlier but the trial is over (offline case)
    if (status == LicenceStatus.trial && daysLeft == 0) status = LicenceStatus.expired;
  }

  void _fromCache() {
    final raw = Store.getString('licence', '');
    if (raw.isNotEmpty) {
      try {
        _apply(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        return;
      } catch (_) {}
    }
    // first launch without network: local trial until the server is reachable
    var first = Store.getInt('first_launch', 0);
    if (first == 0) {
      first = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      Store.setInt('first_launch', first);
    }
    trialEnds = first + trialDays * 86400;
    status = daysLeft > 0 ? LicenceStatus.trial : LicenceStatus.expired;
  }

  /// Asks the server; keeps the last known state when offline.
  Future<LicenceStatus> check() async {
    if (!enabled) return status;
    try {
      final resp = await http
          .post(Uri.parse('$licenceServer/v1/device'),
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'device': device, 'platform': Platform.operatingSystem}))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final j = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
        await Store.setString('licence', resp.body);
        _apply(j);
      }
    } catch (_) {
      // offline: cached state (already applied)
    }
    notifyListeners();
    return status;
  }
}

/// Stable device code shown like a MAC address (Android no longer gives apps
/// the real MAC). Derived from ANDROID_ID / Windows MachineGuid, hashed so no
/// hardware identifier leaves the device.
Future<String> deviceCode() async {
  final cached = Store.getString('device_code', '');
  if (cached.isNotEmpty) return cached;
  String raw = '';
  try {
    if (Platform.isAndroid) {
      raw = await const AndroidId().getId() ?? '';
    } else if (Platform.isWindows) {
      raw = (await DeviceInfoPlugin().windowsInfo).deviceId;
    } else if (Platform.isLinux) {
      raw = (await DeviceInfoPlugin().linuxInfo).machineId ?? '';
    } else if (Platform.isMacOS) {
      raw = (await DeviceInfoPlugin().macOsInfo).systemGUID ?? '';
    }
  } catch (_) {}
  if (raw.isEmpty) {
    final r = Random.secure();
    raw = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
  final bytes = sha256.convert(utf8.encode('maxstream:${Platform.operatingSystem}:$raw')).bytes.sublist(0, 6);
  bytes[0] = (bytes[0] & 0xFC) | 0x02; // locally administered, unicast
  final code = bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
  await Store.setString('device_code', code);
  return code;
}
