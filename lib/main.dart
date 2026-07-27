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
      // 모바일 앱 — 넓은 화면(웹/태블릿)에선 최대 폭 500으로 가운데 정렬.
      builder: (context, child) {
        final size = MediaQuery.of(context).size;
        final contentW = size.width < 500 ? size.width : 500.0;
        return SizedBox(
          width: size.width,
          height: size.height,
          child: ColoredBox(
            color: t.canvas,
            child: Align(
              alignment: Alignment.topCenter,
              child: ClipRect(
                child: SizedBox(
                  width: contentW,
                  height: size.height,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      home: HomePage(repository: repository),
    );
  }
}
