import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:sv_timestamp/l10n/app_localizations.dart';

import 'package:sv_timestamp/screens/camera_screen.dart';
import 'package:sv_timestamp/theme/app_theme.dart';
import 'package:sv_timestamp/utils/emoji_manager.dart';
import 'package:sv_timestamp/utils/metadata_service.dart';
import 'package:sv_timestamp/utils/setting_provider.dart';
import 'package:sv_timestamp/utils/storage_service.dart';
import 'package:sv_timestamp/utils/app_shortcuts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EmojiManager.init();
  await Hive.initFlutter();
  await MetadataService.initializeSettings(const Locale('km'));

  await MetadataService.loadKhmerFont();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StorageService()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, _) {
          final isKhmer = settingsProvider.currentLocale.languageCode == 'km';
          return MaterialApp(
            title: 'SV TimeStamp',
            theme: ThemeData(fontFamily: isKhmer ? 'KantumruyPro' : null),
            darkTheme: AppTheme.darkTheme,
            locale: settingsProvider.currentLocale,
            supportedLocales: const [Locale('en', 'US'), Locale('km', 'KH')],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const CameraScreenWithShortcuts(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

/// Wrapper widget to initialize shortcuts
class CameraScreenWithShortcuts extends StatefulWidget {
  const CameraScreenWithShortcuts({super.key});

  @override
  State<CameraScreenWithShortcuts> createState() =>
      _CameraScreenWithShortcutsState();
}

class _CameraScreenWithShortcutsState extends State<CameraScreenWithShortcuts> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppShortcuts.initialize(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const CameraScreen();
  }
}
