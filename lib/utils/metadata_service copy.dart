import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

class MetadataService {
  static Map<String, img.Image> _emojiCache = {};

  static String? _customLogoPath;
  static String? _customLogoBase64;
  static String _appTitle = '';

  static double? _watermarkSize;

  static String get appTitle => _appTitle;

  static Future<void> initializeSettings(Locale locale) async {
    _currentLocale = locale;
    final prefs = await SharedPreferences.getInstance();

    _appTitle = prefs.getString('app_title') ?? '';
    _customLogoPath = prefs.getString('custom_logo_path');
    _watermarkSize = prefs.getDouble('watermark_size');

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

      final placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isEmpty) {
        print('No placemarks found for coordinates');
        return null;
      }

      final place = placemarks.first;
      String address = "";

      if (place.name != null && place.name!.isNotEmpty) {
        address += place.name!;
      }

      if (place.street != null && place.street!.isNotEmpty) {
        if (address.isNotEmpty) address += ", ";
        address += place.street!;
      }

      if (place.subLocality != null && place.subLocality!.isNotEmpty) {
        if (address.isNotEmpty) address += ", ";
        address += place.subLocality!;
      }

      if (place.locality != null && place.locality!.isNotEmpty) {
        if (address.isNotEmpty) address += ", ";
        address += place.locality!;
      }

      if (place.subAdministrativeArea != null &&
          place.subAdministrativeArea!.isNotEmpty) {
        if (address.isNotEmpty) address += ", ";
        address += place.subAdministrativeArea!;
      }

      if (place.administrativeArea != null &&
          place.administrativeArea!.isNotEmpty) {
        if (address.isNotEmpty) address += ", ";
        address += place.administrativeArea!;
      }

      if (place.postalCode != null && place.postalCode!.isNotEmpty) {
        if (address.isNotEmpty) address += ", ";
        address += place.postalCode!;
      }

      if (place.country != null && place.country!.isNotEmpty) {
        if (address.isNotEmpty) address += ", ";
        address += place.country!;
      }

      print('Detailed address found: $address');
      return address.isNotEmpty ? address : null;
    } catch (e) {
      print('Geocoding error: $e');
      return null;
    }
  }

  static Future<img.Image?> loadLogoImage() async {
    try {
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

      try {
        final ByteData data = await rootBundle.load('assets/sv_super_logo.png');
        final Uint8List bytes = data.buffer.asUint8List();
        final image = img.decodeImage(bytes);
        if (image != null) {
          print('Loaded default logo from assets');
          return image;
        }
      } catch (e) {
        print('Error loading default logo: $e');
      }

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

  static void clearCustomLogo() {
    _customLogoPath = null;
    _customLogoBase64 = null;

    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('custom_logo_path');
    });
  }

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
    return await _addMetadataToImage(
      originalImage,
      timestamp,
      location,
      address,
      locationLabel: locationLabel,
      addressLabel: addressLabel,
      datetimeLabel: datetimeLabel,
    );
  }

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

  static final Map<String, List<String>> _months = {
    'en': [
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
    ],
    'km': [
      'មករា',
      'កុម្ភៈ',
      'មីនា',
      'មេសា',
      'ឧសភា',
      'មិថុនា',
      'កក្កដា',
      'សីហា',
      'កញ្ញា',
      'តុលា',
      'វិច្ឆិកា',
      'ធ្នូ',
    ],
  };

  static final Map<String, List<String>> _days = {
    'en': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    'km': ['ច័ន្ទ', 'អង្គារ', 'ពុធ', 'ព្រហស្បតិ៍', 'សុក្រ', 'សៅរ៍', 'អាទិត្យ'],
  };

  static Locale _currentLocale = const Locale('km');

  static void setCurrentLocale(Locale locale) {
    _currentLocale = locale;
  }

  static Future<void> loadKhmerFont() async {
    final fontLoader = FontLoader('KantumruyPro')
      ..addFont(rootBundle.load('assets/fonts/KantumruyPro-Regular.ttf'));

    await fontLoader.load();
    print('Khmer font loaded successfully');
  }

  // Main method to add metadata to image with maximum quality preservation
  static Future<Uint8List> _addMetadataToImage(
    Uint8List originalImage,
    DateTime timestamp,
    Map<String, double>? location,
    String? address, {
    String? locationLabel,
    String? addressLabel,
    String? datetimeLabel,
  }) async {
    // Decode image with high quality settings
    img.Image? image = img.decodeImage(originalImage);
    if (image == null) return originalImage;

    // Create a working copy with original dimensions
    img.Image workingImage = img.copyResize(
      image,
      width: image.width,
      height: image.height,
      interpolation: img.Interpolation.nearest,
    );

    final languageCode = _currentLocale.languageCode;
    final months = _months[languageCode] ?? _months['en']!;
    final days = _days[languageCode] ?? _days['en']!;

    final hour12 = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final amPm = timestamp.hour >= 12 ? 'PM' : 'AM';

    String dateText;
    if (languageCode == 'km') {
      dateText =
          'ថ្ងៃទី${timestamp.day} ${months[timestamp.month - 1]} ${timestamp.year}, '
          'ថ្ងៃ${days[timestamp.weekday - 1]}';
    } else {
      dateText =
          '${timestamp.day} ${months[timestamp.month - 1]} ${timestamp.year}, '
          '${days[timestamp.weekday - 1]}';
    }

    final prefs = await SharedPreferences.getInstance();
    final double fontSizeDouble = prefs.getDouble('watermark_size') ?? 25.0;
    final int fontSize = fontSizeDouble.toInt();
    final int lineHeight = (fontSize * 1.4).toInt();
    const int leftMargin = 40;
    const int bottomPadding = 40;

    final logoImage = await loadLogoImage();
    final logo = logoImage != null
        ? img.copyResize(
            logoImage,
            width: (workingImage.width * 0.35).toInt(),
            height: (workingImage.height * 0.15).toInt(),
            interpolation: img.Interpolation.linear,
          )
        : null;
    final spacingAfterLogo = logo != null ? 40 : 0;

    final wrappedAddressLines = address != null && address.isNotEmpty
        ? _wrapText(
            '$locationLabel $address',
            fontSize,
            workingImage.width - 100,
          )
        : <String>[];

    final totalTextLines =
        1 + 1 + wrappedAddressLines.length + (location != null ? 1 : 0);
    final logoHeight = logo?.height ?? 0;
    final totalWatermarkHeight =
        logoHeight + spacingAfterLogo + totalTextLines * lineHeight;

    int currentY = workingImage.height - totalWatermarkHeight - bottomPadding;
    if (currentY < 20) currentY = 20;

    // Draw logo
    if (logo != null) {
      // final maxLogoHeight = workingImage.height - currentY - 20;
      final maxLogoHeight = (workingImage.height - currentY - 10).clamp(
        0,
        workingImage.height,
      );

      final logoToDraw = logo.height > maxLogoHeight
          ? img.copyResize(
              logo,
              width: 550,
              height: 550,
              interpolation: img.Interpolation.linear,
            )
          : logo;

      img.compositeImage(
        workingImage,
        logoToDraw,
        dstX: leftMargin,
        dstY: currentY,
      );

      currentY += logoToDraw.height + spacingAfterLogo;
    }

    final timeText =
        '$datetimeLabel ${hour12.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')} $amPm | $dateText';

    // Draw datetime text
    if (languageCode == 'km' && _containsKhmerText(timeText)) {
      workingImage = await _drawTextWithFlutter(
        workingImage,
        timeText,
        leftMargin,
        currentY,
        fontSize,
        isKhmer: true,
      );
    } else {
      _drawText(workingImage, timeText, leftMargin, currentY, fontSize);
    }

    currentY += lineHeight + 1;

    // Draw address lines
    for (var line in wrappedAddressLines) {
      if (currentY + lineHeight > workingImage.height - 20) break;

      if (languageCode == 'km' && _containsKhmerText(line)) {
        workingImage = await _drawTextWithFlutter(
          workingImage,
          line,
          leftMargin,
          currentY,
          fontSize,
          isKhmer: true,
        );
      } else {
        _drawText(workingImage, line, leftMargin, currentY, fontSize);
      }

      currentY += lineHeight;
    }

    // Draw location coordinates
    if (location != null && currentY + lineHeight <= workingImage.height - 20) {
      final lat = location['latitude']!;
      final lng = location['longitude']!;
      final latH = lat >= 0 ? 'N' : 'S';
      final lngH = lng >= 0 ? 'E' : 'W';

      final latLongText = languageCode == 'km'
          ? 'ទីតាំង: ${lat.abs().toStringAsFixed(6)}°$latH, ${lng.abs().toStringAsFixed(6)}°$lngH'
          : 'Lat/Long: ${lat.abs().toStringAsFixed(6)}°$latH, ${lng.abs().toStringAsFixed(6)}°$lngH';

      if (languageCode == 'km') {
        workingImage = await _drawTextWithFlutter(
          workingImage,
          latLongText,
          leftMargin,
          currentY,
          fontSize,
          isKhmer: true,
        );
      } else {
        _drawText(workingImage, latLongText, leftMargin, currentY, fontSize);
      }
    }

    // Encode with maximum quality (100 = lossless for JPEG)
    return Uint8List.fromList(img.encodeJpg(workingImage, quality: 100));
  }

  static bool _containsKhmerText(String text) {
    final khmerRegex = RegExp(r'[\u1780-\u17FF]');
    return khmerRegex.hasMatch(text);
  }

  // Draw text using Flutter's text renderer for complex scripts
  static Future<img.Image> _drawTextWithFlutter(
    img.Image image,
    String text,
    int x,
    int y,
    int fontSize, {
    bool isKhmer = false,
    Color? color,
    bool shadow = true,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Convert img.Image to ui.Image for drawing
      final uiImage = await _convertToUiImage(image);
      canvas.drawImage(uiImage, Offset.zero, Paint());

      final textStyle = TextStyle(
        fontSize: fontSize.toDouble(),
        color: color ?? Colors.white,
        fontFamily: isKhmer ? 'KantumruyPro' : null,
        height: 1.2,
      );

      final textSpan = TextSpan(text: text, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      if (shadow) {
        final shadowPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: textStyle.copyWith(color: Colors.black.withAlpha(128)),
          ),
          textDirection: TextDirection.ltr,
        );
        shadowPainter.layout();
        shadowPainter.paint(canvas, Offset(x + 1.0, y + 1.0));
      }

      textPainter.paint(canvas, Offset(x.toDouble(), y.toDouble()));

      final picture = recorder.endRecording();
      final newUiImage = await picture.toImage(image.width, image.height);
      final byteData = await newUiImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      if (byteData != null) {
        // Create new image from raw RGBA data without compression
        final rgbaBytes = byteData.buffer.asUint8List();
        final newImage = img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: rgbaBytes.buffer,
          numChannels: 4,
        );
        return newImage;
      }

      return image;
    } catch (e) {
      print('Error in _drawTextWithFlutter: $e');
      _drawText(image, text, x, y, fontSize, color: color, shadow: shadow);
      return image;
    }
  }

  // Convert img.Image to ui.Image with direct pixel manipulation
  static Future<ui.Image> _convertToUiImage(img.Image image) async {
    final completer = Completer<ui.Image>();

    // Direct conversion without PNG encoding
    final bytes = Uint8List(image.width * image.height * 4);
    int offset = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        bytes[offset++] = pixel.r.toInt();
        bytes[offset++] = pixel.g.toInt();
        bytes[offset++] = pixel.b.toInt();
        bytes[offset++] = pixel.a.toInt();
      }
    }

    ui.decodeImageFromPixels(
      bytes,
      image.width,
      image.height,
      ui.PixelFormat.rgba8888,
      (ui.Image result) {
        completer.complete(result);
      },
    );

    return completer.future;
  }

  // Wrap text to fit within maxWidth
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

        while (_measureTextWidth(currentLine, font) > maxWidth &&
            currentLine.length > 1) {
          int cutIndex =
              (currentLine.length *
                      maxWidth /
                      _measureTextWidth(currentLine, font))
                  .floor();
          if (cutIndex < 1) cutIndex = 1;
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

  // Measure text width using bitmap font
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

  // Draw text using bitmap font (fallback method)
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
      img.drawString(image, text, font: font, x: x, y: y, color: textColor);
    }
  }

  // Get appropriate bitmap font for font size
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
      return img.arial48;
    } else {
      return img.arial48;
    }
  }
}
