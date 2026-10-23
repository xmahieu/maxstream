import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'licence.dart';
import 'screens/home.dart';
import 'screens/licence_screen.dart';
import 'session.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Store.init();
  Session.I.load();
  await Licence.I.init();
  runApp(const MaxStreamApp());
}

final navigatorKey = GlobalKey<NavigatorState>();

class BackIntent extends Intent {
  const BackIntent();
}

class MaxStreamApp extends StatelessWidget {
  const MaxStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      // TV remotes: OK / centre button activates like Enter
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.escape): BackIntent(),
        SingleActivator(LogicalKeyboardKey.browserBack): BackIntent(),
      },
      child: Actions(
        actions: {
          BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
            navigatorKey.currentState?.maybePop();
            return null;
          }),
        },
        child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'MaxStream',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: (context, child) => LicenceGate(child: child ?? const SizedBox.shrink()),
        home: const HomeScreen(),
        ),
      ),
    );
  }
}
