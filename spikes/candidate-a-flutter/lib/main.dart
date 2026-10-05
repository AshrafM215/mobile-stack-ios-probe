// G1 candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Synthetic wayfinding benchmark app (G1-CIC-1.0). Not a product; synthetic data only; not for navigation.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/app_state.dart';
import 'src/core/strings.dart';
import 'src/lab/lab.dart';
import 'src/ui/screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final strings = {
    'en': Strings.parse('en', await rootBundle.loadString('assets/strings/en.json')),
    'ar': Strings.parse('ar', await rootBundle.loadString('assets/strings/ar.json')),
  };
  final state = AppState(strings);
  AppLifecycleListener(onResume: state.onResumed);
  runApp(G1App(state: state));
  await state.boot();
  unawaited(LabController(state).start());
}
