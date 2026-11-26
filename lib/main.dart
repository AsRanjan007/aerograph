import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app/settings.dart';
import 'ui/brand.dart';
import 'ui/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  final settings = await AppSettings.load();
  runApp(AerographApp(settings: settings));
}

class AerographApp extends StatelessWidget {
  const AerographApp({super.key, required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.violet,
      brightness: Brightness.dark,
      surface: Brand.night,
    );
    return MaterialApp(
      title: 'Aerograph',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: Brand.night,
        sliderTheme: const SliderThemeData(activeTrackColor: Brand.orchid, thumbColor: Colors.white),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      home: SplashScreen(settings: settings),
    );
  }
}
