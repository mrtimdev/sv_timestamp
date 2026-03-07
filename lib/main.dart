// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:svs_timestamp/constants/app_colors.dart';
import 'package:svs_timestamp/screens/home_screen.dart';
import 'package:svs_timestamp/utils/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => StorageService(),
      child: MaterialApp(
        title: 'SVS Timestamp',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: AppColors.primaryColor,
          colorScheme: ColorScheme.light(
            primary: AppColors.primaryBlue,
            secondary: AppColors.secondaryBlue,
          ),
          fontFamily: 'Poppins', // Optional: add a nice font
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
