import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'services/app_config.dart';
import 'services/notifications.dart';
import 'services/repository.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart' as t;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

  await TideNotifications.init();

  final config = await AppConfig.load();
  runApp(BiteWindApp(repository: Repository(config)));
}

class BiteWindApp extends StatelessWidget {
  final Repository repository;

  const BiteWindApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TideUp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        fontFamily: t.fontFamily,
        scaffoldBackgroundColor: t.canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: t.ink,
          brightness: Brightness.light,
          surface: t.canvas,
        ),
      ),
      home: HomePage(repository: repository),
    );
  }
}
