import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:svs_timestamp/utils/metadata_service.dart';

class SettingsProvider with ChangeNotifier {
  Locale _currentLocale = const Locale('km');
  Locale get currentLocale => _currentLocale;

  void changeLocale(Locale newLocale) {
    _currentLocale = newLocale;
    MetadataService.setCurrentLocale(newLocale);

    setLocaleIdentifier(
      newLocale.countryCode != null
          ? '${newLocale.languageCode}_${newLocale.countryCode}'
          : newLocale.languageCode,
    );
    notifyListeners();
  }
}
