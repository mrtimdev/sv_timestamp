// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:svs_timestamp/constants/app_colors.dart';
import 'package:svs_timestamp/screens/home_screen.dart';
import 'package:svs_timestamp/utils/storage_service.dart';
import 'package:svs_timestamp/utils/setting_provider.dart';
import 'package:svs_timestamp/l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      child: Builder(
        builder: (context) {
          final settingsProvider = context.watch<SettingsProvider>();
          return MaterialApp(
            title: 'SVS Timestamp',
            debugShowCheckedModeBanner: false,
            locale: settingsProvider.currentLocale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(
              primaryColor: AppColors.primaryColor,
              colorScheme: ColorScheme.light(
                primary: AppColors.primaryBlue,
                secondary: AppColors.secondaryBlue,
              ),
              fontFamily: 'Poppins', // Optional: add a nice font
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
