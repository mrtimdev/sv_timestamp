import 'package:flutter/material.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:svs_timestamp/screens/SettingsScreen.dart';
import 'package:svs_timestamp/screens/camera_screen.dart';
import 'package:svs_timestamp/screens/full_screen_image_viewer.dart';
import 'package:svs_timestamp/utils/storage_service.dart';
import 'package:provider/provider.dart';

class AppShortcuts {
  static const String _cameraAction = 'camera';
  static const String _galleryAction = 'gallery';
  static const String _settingsAction = 'settings';
  static const String _lastPhotoAction = 'last_photo';

  static final QuickActions quickActions = QuickActions();

  // Store the context for later use
  static BuildContext? _storedContext;

  static void initialize(BuildContext context) {
    _storedContext = context;

    quickActions.initialize((String shortcutType) async {
      // Handle shortcut tap
      if (_storedContext != null) {
        _handleShortcut(shortcutType, _storedContext!);
      }
    });

    // Set up the shortcuts
    _setupShortcuts();
  }

  static void updateContext(BuildContext context) {
    _storedContext = context;
  }

  static void _setupShortcuts() {
    quickActions.setShortcutItems(<ShortcutItem>[
      ShortcutItem(
        type: _cameraAction,
        localizedTitle: 'Open Camera',
        icon: 'ic_camera',
      ),
      ShortcutItem(
        type: _galleryAction,
        localizedTitle: 'View Gallery',
        icon: 'ic_gallery',
      ),
      ShortcutItem(
        type: _settingsAction,
        localizedTitle: 'Settings',
        icon: 'ic_settings',
      ),
      ShortcutItem(
        type: _lastPhotoAction,
        localizedTitle: 'Last Photo',
        icon: 'ic_last_photo',
      ),
    ]);
  }

  static void _handleShortcut(String shortcutType, BuildContext context) {
    // Ensure we're in the widget tree
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleShortcutInternal(shortcutType, context);
    });
  }

  static void _handleShortcutInternal(
    String shortcutType,
    BuildContext context,
  ) {
    switch (shortcutType) {
      case _cameraAction:
        _navigateToCamera(context);
        break;
      case _galleryAction:
        _openGallery(context);
        break;
      case _settingsAction:
        _navigateToSettings(context);
        break;
      case _lastPhotoAction:
        _openLastPhoto(context);
        break;
    }
  }

  static void _navigateToCamera(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const CameraScreen()),
      (route) => route.isFirst,
    );
  }

  static void _openGallery(BuildContext context) {
    final storageService = Provider.of<StorageService>(context, listen: false);

    if (storageService.capturedImages.isNotEmpty) {
      // Navigate to camera screen and show snackbar hint
      Navigator.of(context)
          .pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const CameraScreen()),
            (route) => route.isFirst,
          )
          .then((_) {
            // Show hint about gallery button
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Tap the gallery button in the bottom left corner',
                ),
                duration: Duration(seconds: 3),
              ),
            );
          });
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const CameraScreen()),
        (route) => route.isFirst,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No photos available'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  static void _navigateToSettings(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
      (route) => route.isFirst,
    );
  }

  static void _openLastPhoto(BuildContext context) {
    final storageService = Provider.of<StorageService>(context, listen: false);

    if (storageService.capturedImages.isNotEmpty) {
      final lastImage = storageService.capturedImages.first;

      // Navigate directly to the full screen image viewer
      Navigator.of(context)
          .pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const CameraScreen()),
            (route) => route.isFirst,
          )
          .then((_) {
            // Navigate to full screen viewer
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FullScreenImageViewer(image: lastImage),
              ),
            );
          });
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const CameraScreen()),
        (route) => route.isFirst,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No photos available'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // Update shortcuts dynamically (e.g., when new photo is taken)
  static void updateLastPhotoShortcut(int photoCount) {
    if (photoCount > 0) {
      // Update the last photo shortcut
      quickActions.setShortcutItems(<ShortcutItem>[
        ShortcutItem(
          type: _cameraAction,
          localizedTitle: 'Open Camera',
          icon: 'ic_camera',
        ),
        ShortcutItem(
          type: _galleryAction,
          localizedTitle: 'View Gallery',
          icon: 'ic_gallery',
        ),
        ShortcutItem(
          type: _settingsAction,
          localizedTitle: 'Settings',
          icon: 'ic_settings',
        ),
        ShortcutItem(
          type: _lastPhotoAction,
          localizedTitle: photoCount > 1 ? 'Last Photo' : 'View Photo',
          icon: 'ic_last_photo',
        ),
      ]);
    }
  }
}
