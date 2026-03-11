import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sv_timestamp/l10n/app_localizations.dart';

class MetadataService {
  static Map<String, img.Image> _emojiCache = {};

  static String? _customLogoPath;
  static String? _customLogoBase64;
  static String _appTitle = '';

  // static int fontSize = 20;

  static double? _watermarkSize;

  // static double? get watermarkSize => _watermarkSize;
  static String get appTitle => _appTitle;

  static Future<void> initializeSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _appTitle = prefs.getString('app_title') ?? '';
    _customLogoPath = prefs.getString('custom_logo_path');

    _watermarkSize = prefs.getDouble('watermark_size');

    print("_watermarkSize: $_watermarkSize");

    // If custom logo path exists, load it
    if (_customLogoPath != null && File(_customLogoPath!).existsSync()) {
      try {
        final bytes = await File(_customLogoPath!).readAsBytes();
        _customLogoBase64 = String.fromCharCodes(bytes);
      } catch (e) {
        print('Error loading custom logo: $e');
        _customLogoPath = null;
      }
    }
  }

  static Future<void> setCustomLogoPath(String? path) async {
    _customLogoPath = path;
    _customLogoBase64 = null;

    if (path != null) {
      try {
        final bytes = await File(path).readAsBytes();
        _customLogoBase64 = String.fromCharCodes(bytes);
      } catch (e) {
        print('Error loading new custom logo: $e');
      }
    }

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString('custom_logo_path', path);
    } else {
      await prefs.remove('custom_logo_path');
    }
  }

  static void setAppTitle(String title) {
    _appTitle = title.isNotEmpty ? title : '';
  }

  // Get GPS Coordinates
  static Future<Map<String, double>?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          return null;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return {'latitude': position.latitude, 'longitude': position.longitude};
    } catch (e) {
      return null;
    }
  }

  static Future<String?> getAddressFromCoordinates(
    double lat,
    double lng,
  ) async {
    try {
      print('Getting address for coordinates: $lat, $lng');

      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        String address = "";

        // Build address gradually
        if (place.street != null && place.street!.isNotEmpty) {
          address += place.street!;
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          if (address.isNotEmpty) address += ", ";
          address += place.locality!;
        }
        if (place.administrativeArea != null &&
            place.administrativeArea!.isNotEmpty) {
          if (address.isNotEmpty) address += ", ";
          address += place.administrativeArea!;
        }
        if (place.country != null && place.country!.isNotEmpty) {
          if (address.isNotEmpty) address += ", ";
          address += place.country!;
        }

        print('Address found: $address');
        return address.isNotEmpty ? address : null;
      } else {
        print('No placemarks found for coordinates');
        return null;
      }
    } catch (e) {
      print('Geocoding error: $e');
      return null;
    }
  }

  static Future<img.Image?> loadLogoImage() async {
    try {
      // Try to load custom logo first
      if (_customLogoBase64 != null && _customLogoBase64!.isNotEmpty) {
        try {
          final bytes = Uint8List.fromList(_customLogoBase64!.codeUnits);
          final image = img.decodeImage(bytes);
          if (image != null) {
            print('Loaded custom logo successfully');
            return image;
          }
        } catch (e) {
          print('Error decoding custom logo: $e');
        }
      }

      // Fall back to default logo
      try {
        final ByteData data = await rootBundle.load('assets/logo.png');
        final Uint8List bytes = data.buffer.asUint8List();
        final image = img.decodeImage(bytes);
        if (image != null) {
          print('Loaded default logo from assets');
          return image;
        }
      } catch (e) {
        print('Error loading default logo: $e');
      }

      // Try to load from custom file path if base64 failed
      if (_customLogoPath != null) {
        try {
          final bytes = await File(_customLogoPath!).readAsBytes();
          final image = img.decodeImage(bytes);
          if (image != null) {
            print('Loaded custom logo from file path');
            return image;
          }
        } catch (e) {
          print('Error loading logo from file: $e');
        }
      }

      return null;
    } catch (e) {
      print('Error in loadLogoImage: $e');
      return null;
    }
  }

  // Clear custom logo cache
  static void clearCustomLogo() {
    _customLogoPath = null;
    _customLogoBase64 = null;

    // Clear from SharedPreferences
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('custom_logo_path');
    });
  }

  // Check if custom logo is set
  static bool hasCustomLogo() {
    return _customLogoPath != null ||
        (_customLogoBase64 != null && _customLogoBase64!.isNotEmpty);
  }

  static String? getCustomLogoPath() {
    return _customLogoPath;
  }

  static Future<Uint8List> addMetadataToImage(
    Uint8List originalImage,
    DateTime timestamp,
    Map<String, double>? location,
    String? address, {
    String? locationLabel,
    String? addressLabel,
    String? datetimeLabel,
  }) async {
    return await _legacyAddMetadataToImage(
      originalImage,
      timestamp,
      location,
      address,
      locationLabel: locationLabel,
      addressLabel: addressLabel,
      datetimeLabel: datetimeLabel,
    );
  }

  // Initialize emoji cache (call this once at app startup)
  static Future<void> initEmojiCache() async {
    final emojiPaths = {
      '🕘': 'assets/clock_emoji.png',
      '📅': 'assets/calendar_emoji.png',
      '📍': 'assets/location_emoji.png',
      '🏠': 'assets/house_emoji.png',
    };

    for (final entry in emojiPaths.entries) {
      try {
        final file = File(entry.value);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final emojiImage = img.decodeImage(bytes);
          if (emojiImage != null) {
            _emojiCache[entry.key] = img.copyResize(
              emojiImage,
              width: 40,
              height: 40,
            );
          }
        }
      } catch (e) {
        print('Error loading emoji ${entry.key}: $e');
      }
    }
  }

  static Future<Uint8List> _legacyAddMetadataToImage(
    Uint8List originalImage,
    DateTime timestamp,
    Map<String, double>? location,
    String? address, {
    String? locationLabel,
    String? addressLabel,
    String? datetimeLabel,
  }) async {
    img.Image? image = img.decodeImage(originalImage);
    if (image == null) return originalImage;

    // ---- TIME FORMAT ----
    final hour12 = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final amPm = timestamp.hour >= 12 ? 'PM' : 'AM';

    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    print(
      "locationLabel: $locationLabel, addressLabel: $addressLabel, datetimeLabel: $datetimeLabel",
    );

    final dateText =
        '${timestamp.day} ${months[timestamp.month - 1]} ${timestamp.year}, '
        '${days[timestamp.weekday - 1]}';

    // ---- STYLES ----
    final prefs = await SharedPreferences.getInstance();
    final double fontSizeDouble = prefs.getDouble('watermark_size') ?? 25.0;
    final int fontSize = fontSizeDouble.toInt();
    final int lineHeight = (fontSize * 1.4).toInt();
    const int leftMargin = 40;
    const int bottomPadding = 40;

    // ---- LOGO ----
    final logoImage = await loadLogoImage();
    final logo = logoImage != null
        ? img.copyResize(logoImage, width: 250)
        : null;
    final spacingAfterLogo = logo != null ? 40 : 0;

    // ---- ADDRESS WRAP ----
    final wrappedAddressLines = address != null && address.isNotEmpty
        ? _wrapText('$locationLabel $address', fontSize, image.width - 100)
        : <String>[];

    // ---- TOTAL LINES ----
    final totalTextLines =
        1 +
        1 +
        wrappedAddressLines.length +
        (location != null ? 1 : 0); // title + datetime + address + latlng
    final logoHeight = logo?.height ?? 0;
    final totalWatermarkHeight =
        logoHeight + spacingAfterLogo + totalTextLines * lineHeight;

    // ---- SAFE START Y ----
    int currentY = image.height - totalWatermarkHeight - bottomPadding;
    if (currentY < 20) currentY = 20;

    // ---- DRAW LOGO ----
    if (logo != null) {
      final maxLogoHeight = image.height - currentY - 20; // clamp
      final logoToDraw = logo.height > maxLogoHeight
          ? img.copyResize(logo, height: maxLogoHeight)
          : logo;

      for (int y = 0; y < logoToDraw.height; y++) {
        for (int x = 0; x < logoToDraw.width; x++) {
          final p = logoToDraw.getPixel(x, y);
          if (p.a == 0) continue;

          final tx = leftMargin + x;
          final ty = currentY + y;

          if (tx < 0 || ty < 0 || tx >= image.width || ty >= image.height)
            continue;

          final bg = image.getPixel(tx, ty);
          final a = p.a / 255.0;

          image.setPixelRgba(
            tx,
            ty,
            (p.r * a + bg.r * (1 - a)).toInt(),
            (p.g * a + bg.g * (1 - a)).toInt(),
            (p.b * a + bg.b * (1 - a)).toInt(),
            255,
          );
        }
      }
      currentY += logoToDraw.height + spacingAfterLogo;
    }

    // ---- DRAW TITLE ----
    // _drawText(
    //   image,
    //   _appTitle,
    //   leftMargin,
    //   currentY,
    //   fontSize + 2,
    //   stroke: true,
    //   bold: true,
    // );
    // currentY += lineHeight;

    // ---- DRAW DATETIME ----

    final timeText =
        '$datetimeLabel ${hour12.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')} $amPm | $dateText';
    _drawText(image, timeText, leftMargin, currentY, fontSize);

    currentY += lineHeight + 1;

    // ---- DRAW ADDRESS (MULTI-LINE) ----
    for (var line in wrappedAddressLines) {
      if (currentY + lineHeight > image.height - 20) break; // prevent overflow
      _drawText(image, line, leftMargin, currentY, fontSize);
      currentY += lineHeight;
    }

    // ---- DRAW LAT/LONG ----
    if (location != null && currentY + lineHeight <= image.height - 20) {
      final lat = location['latitude']!;
      final lng = location['longitude']!;
      final latH = lat >= 0 ? 'N' : 'S';
      final lngH = lng >= 0 ? 'E' : 'W';

      _drawText(
        image,
        'Lat/Long: ${lat.abs().toStringAsFixed(6)}°$latH, ${lng.abs().toStringAsFixed(6)}°$lngH',
        leftMargin,
        currentY,
        fontSize,
      );
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  /// Wraps text into multiple lines that fit within maxWidth
  static List<String> _wrapText(String text, int fontSize, int maxWidth) {
    final font = _getFontForSize(fontSize);
    final words = text.split(' ');
    final lines = <String>[];
    String currentLine = '';

    for (var word in words) {
      final testLine = currentLine.isEmpty ? word : '$currentLine $word';
      if (_measureTextWidth(testLine, font) <= maxWidth) {
        currentLine = testLine;
      } else {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine);
        }
        currentLine = word;

        // Word itself is longer than maxWidth, split forcibly
        while (_measureTextWidth(currentLine, font) > maxWidth &&
            currentLine.length > 1) {
          int cutIndex =
              (currentLine.length *
                      maxWidth /
                      _measureTextWidth(currentLine, font))
                  .floor();
          final part = currentLine.substring(0, cutIndex);
          lines.add(part);
          currentLine = currentLine.substring(cutIndex);
        }
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    return lines;
  }

  static String _truncateSingleLine(String text, int fontSize, int maxWidth) {
    final font = _getFontForSize(fontSize);

    if (_measureTextWidth(text, font) <= maxWidth) return text;

    String result = text;
    while (result.isNotEmpty &&
        _measureTextWidth('$result...', font) > maxWidth) {
      result = result.substring(0, result.length - 1);
    }
    return '$result...';
  }

  // Helper method to measure text width
  static int _measureTextWidth(String text, img.BitmapFont font) {
    int width = 0;
    for (int i = 0; i < text.length; i++) {
      final char = text.codeUnitAt(i);
      final charData = font.characters[char];
      if (charData != null) {
        width += charData.xAdvance;
      }
    }
    return width;
  }

  // Keep your existing _drawText method
  static void _drawText(
    img.Image image,
    String text,
    int x,
    int y,
    int fontSize, {
    Color? color,
    bool shadow = true,
    bool stroke = false,
    bool bold = false,
  }) {
    final font = _getFontForSize(fontSize);

    final textColor = img.ColorRgb8(
      color?.red ?? 255,
      color?.green ?? 255,
      color?.blue ?? 255,
    );

    if (stroke) {
      final strokeColor = img.ColorRgb8(0, 0, 0);
      const strokeWidth = 1;

      for (int dx = -strokeWidth; dx <= strokeWidth; dx++) {
        for (int dy = -strokeWidth; dy <= strokeWidth; dy++) {
          if (dx == 0 && dy == 0) continue;

          img.drawString(
            image,
            text,
            font: font,
            x: x + dx,
            y: y + dy,
            color: strokeColor,
          );
        }
      }
    }

    if (shadow) {
      img.drawString(
        image,
        text,
        font: font,
        x: x + 1,
        y: y + 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }

    if (bold) {
      for (int i = 0; i < 2; i++) {
        img.drawString(
          image,
          text,
          font: font,
          x: x + i,
          y: y,
          color: textColor,
        );
      }
    } else {
      // ---- NORMAL TEXT ----
      img.drawString(image, text, font: font, x: x, y: y, color: textColor);
    }
  }

  // Update the helper method to support larger font sizes
  static img.BitmapFont _getFontForSize(int fontSize) {
    if (fontSize <= 12) {
      return img.arial14;
    } else if (fontSize <= 18) {
      return img.arial24;
    } else if (fontSize <= 36) {
      return img.arial24;
    } else if (fontSize <= 48) {
      return img.arial48;
    } else if (fontSize <= 72) {
      return img.arial48; // For larger sizes
    } else {
      return img.arial48;
    }
  }
}
