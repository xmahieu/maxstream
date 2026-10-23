import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/home.dart';
import 'session.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Store.init();
  Session.I.load();
  runApp(const MaxStreamApp());
}

class MaxStreamApp extends StatelessWidget {
  const MaxStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      // TV remotes: OK / centre button activates like Enter
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      },
      child: MaterialApp(
        title: 'MaxStream',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeScreen(),
      ),
    );
  }
}
