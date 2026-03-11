import 'dart:io';
import 'dart:math';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:svs_timestamp/l10n/app_localizations.dart';
import 'package:vibration/vibration.dart';
import 'package:svs_timestamp/models/captured_image.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:svs_timestamp/screens/settings_screen.dart';
import 'package:svs_timestamp/screens/gallery_screen.dart';
import '../utils/metadata_service.dart';
import '../utils/storage_service.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // Location
  Map<String, double>? _coords;
  String _address = "Loading...";
  bool _isLocationReady = false;

  // User settings
  SharedPreferences? _prefs;
  bool _soundOn = true;
  bool _vibrateOn = true;
  String _quality = 'High';
  double _watermarkSize = 25.0;

  // Track latest thumbnail from native gallery
  File? _latestThumbnail;

  // Navigation state
  bool _isNavigatingAway = false;
  bool _isDisposed = false;

  // Camera state tracking
  bool _isCapturing = false;
  SensorPosition _currentCamera = SensorPosition.back;

  // Animation controllers for capture button
  late AnimationController _captureAnimController;
  late Animation<double> _captureScaleAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAnimations();
    _init();
  }

  void _initAnimations() {
    _captureAnimController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _captureScaleAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _captureAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _captureAnimController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _init() async {
    try {
      await _loadPrefs();
      await _initLocation();
      await _loadLatestThumbnail();
    } catch (e, stackTrace) {
      print('Initialization error: $e');
      print(stackTrace);
      if (mounted) {
        setState(() {
          _address = "Initialization error";
          _isLocationReady = true;
        });
      }
    }
  }

  Future<void> _loadPrefs() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      if (_isDisposed || !mounted) return;

      setState(() {
        _soundOn = _prefs!.getBool('sound_on_capture') ?? true;
        _vibrateOn = _prefs!.getBool('vibration_on_capture') ?? true;
        _quality = _prefs!.getString('image_quality') ?? 'High';
        _watermarkSize = _prefs!.getDouble('watermark_size') ?? 25.0;

        final title = _prefs!.getString('app_title');
        if (title?.isNotEmpty == true) MetadataService.setAppTitle(title!);

        final logoPath = _prefs!.getString('custom_logo_path');
        if (logoPath != null) MetadataService.setCustomLogoPath(logoPath);
      });
    } catch (e) {
      print('Error loading prefs: $e');
    }
  }

  Future<void> _initLocation() async {
    try {
      final loc = await MetadataService.getCurrentLocation();
      if (_isDisposed || !mounted) return;

      if (loc != null) {
        final addr = await MetadataService.getAddressFromCoordinates(
          loc['latitude']!,
          loc['longitude']!,
        );
        if (mounted) {
          setState(() {
            _coords = loc;
            _address = addr ?? "Unknown";
            _isLocationReady = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _address = "Location unavailable";
            _isLocationReady = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _address = "Location error";
          _isLocationReady = true;
        });
      }
    }
  }

  Future<void> _loadLatestThumbnail() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (permission.isAuth || permission.hasAccess) {
        final filterOption = FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        );

        final albums = await PhotoManager.getAssetPathList(
          type: RequestType.image,
          hasAll: true,
          filterOption: filterOption,
        );
        for (var a in albums) {
          if (a.name == 'SVS-Watermark-Camera') {
            final assets = await a.getAssetListPaged(page: 0, size: 1);
            if (assets.isNotEmpty) {
              final file = await assets.first.file;
              if (file != null && await file.exists()) {
                print('Native PhotoManager thumbnail found: ${file.path}');
                if (mounted) setState(() => _latestThumbnail = file);
                return;
              }
            }
          }
        }
      }

      // Fallback
      if (Platform.isAndroid) {
        final dirs = [
          Directory('/storage/emulated/0/Pictures/SVS-Watermark-Camera'),
          Directory('/storage/emulated/0/DCIM/SVS-Watermark-Camera'),
        ];
        List<File> images = [];
        for (var d in dirs) {
          if (await d.exists()) {
            images.addAll(
              d.listSync().whereType<File>().where(
                (f) =>
                    f.path.toLowerCase().endsWith('.jpg') ||
                    f.path.toLowerCase().endsWith('.jpeg') ||
                    f.path.toLowerCase().endsWith('.png'),
              ),
            );
          }
        }
        if (images.isNotEmpty) {
          images.sort((a, b) {
            try {
              return b.lastModifiedSync().compareTo(a.lastModifiedSync());
            } catch (_) {
              return 0;
            }
          });
          print('Fallback thumbnail found: ${images.first.path}');
          if (mounted) setState(() => _latestThumbnail = images.first);
        } else {
          print('Fallback thumbnail: No images found');
          if (mounted) setState(() => _latestThumbnail = null);
        }
      } else {
        if (mounted) setState(() => _latestThumbnail = null);
      }
    } catch (e) {
      print('Thumbnail load error: $e');
    }
  }

  Future<void> _saveToDeviceGallery(File image) async {
    try {
      if (!await image.exists()) {
        print('File does not exist: ${image.path}');
        return;
      }

      await Future.delayed(const Duration(milliseconds: 100));

      final fileStat = await image.stat();
      print('File size: ${fileStat.size} bytes');

      if (fileStat.size == 0) {
        print('File is empty');
        return;
      }

      final result = await GallerySaver.saveImage(
        image.path,
        albumName: 'SVS-Watermark-Camera',
      );

      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✓ Saved to gallery'),
            backgroundColor: Colors.green,
            duration: const Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      print('Error saving to gallery: $e');
    }
  }

  Future<void> _processAndSaveImage(File imageFile) async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    if (_vibrateOn) {
      try {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          Vibration.vibrate(duration: 50);
        }
      } catch (e) {
        print('Vibration error: $e');
      }
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = path.join(
        tempDir.path,
        'temp_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      await imageFile.rename(tempPath);

      final timestamp = DateTime.now();
      final loc = mounted ? AppLocalizations.of(context) : null;

      final imageBytes = await File(tempPath).readAsBytes();

      final processed = await MetadataService.addMetadataToImage(
        imageBytes,
        timestamp,
        _coords,
        _address,
        locationLabel: loc?.locationLabel ?? 'Location:',
        addressLabel: loc?.addressLabel ?? 'Address:',
        datetimeLabel: loc?.datetimeLabel ?? 'Date:',
      );

      final finalTempPath = path.join(
        tempDir.path,
        'watermarked_${timestamp.millisecondsSinceEpoch}.jpg',
      );
      await File(finalTempPath).writeAsBytes(processed);

      if (await File(tempPath).exists()) {
        await File(tempPath).delete();
      }

      try {
        final storageService = Provider.of<StorageService>(
          context,
          listen: false,
        );

        storageService.capturedImages.insert(
          0,
          CapturedImage(
            id: timestamp.millisecondsSinceEpoch.toString(),
            imagePath: finalTempPath,
            timestamp: timestamp,
            location: _coords,
            address: _address,
            additionalData: {
              'quality': _quality,
              'camera': _currentCamera == SensorPosition.back
                  ? 'Back'
                  : 'Front',
            },
          ),
        );
      } catch (e) {
        print('Provider not found or storage service error: $e');
      }

      final finalFile = File(finalTempPath);
      if (await finalFile.exists()) {
        print('Watermarked image created: ${finalFile.path}');
        await _saveToDeviceGallery(finalFile);

        if (mounted) {
          setState(() {
            _latestThumbnail = finalFile;
          });
        }

        Future.delayed(const Duration(seconds: 2), _loadLatestThumbnail);
      }
    } catch (e) {
      print('Image processing error: $e');
      if (mounted) {
        final errorMsg = e.toString();
        final displayError = errorMsg.length > 50
            ? '${errorMsg.substring(0, 50)}...'
            : errorMsg;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $displayError'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  void _navigateToSettings() async {
    if (_isNavigatingAway) return;

    _isNavigatingAway = true;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );

    if (mounted) {
      _isNavigatingAway = false;
      await _loadPrefs();
    }
  }

  void _showGallery() async {
    if (_isNavigatingAway) return;

    _isNavigatingAway = true;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GalleryScreen()),
    );

    if (mounted) {
      _isNavigatingAway = false;
      await _loadLatestThumbnail();
    }
  }

  void _showWatermarkSettings() {
    if (_isCapturing) return;

    double tempSize = _watermarkSize;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isDismissible: true,
      enableDrag: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Watermark Size',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(Icons.text_fields, color: Colors.white),
                  Expanded(
                    child: Slider(
                      value: tempSize,
                      min: 20,
                      max: 100,
                      divisions: 16,
                      activeColor: Colors.blue,
                      onChanged: (v) => setModalState(() => tempSize = v),
                    ),
                  ),
                  Text(
                    '${tempSize.toInt()}px',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _watermarkSize = tempSize);
                      _prefs?.setDouble('watermark_size', tempSize);
                      Navigator.pop(context);
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _loadLatestThumbnail();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            CameraAwesomeBuilder.awesome(
              onMediaCaptureEvent: (event) {
                switch ((event.status, event.isPicture, event.isVideo)) {
                  case (MediaCaptureStatus.capturing, true, false):
                    debugPrint('Capturing picture...');
                  case (MediaCaptureStatus.success, true, false):
                    event.captureRequest.when(
                      single: (single) {
                        if (single.file != null) {
                          final file = File(single.file!.path);
                          _processAndSaveImage(file);
                        }
                      },
                      multiple: (multiple) {
                        multiple.fileBySensor.forEach((key, value) {
                          if (value != null) {
                            final file = File(value.path);
                            _processAndSaveImage(file);
                          }
                        });
                      },
                    );
                  case (MediaCaptureStatus.failure, true, false):
                    debugPrint('Failed to capture picture: ${event.exception}');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Capture failed: ${event.exception}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  default:
                    // Handle other events if needed
                    break;
                }
              },
              saveConfig: SaveConfig.photo(
                pathBuilder: (sensors) async {
                  final Directory extDir = await getTemporaryDirectory();
                  final testDir = await Directory(
                    '${extDir.path}/camerawesome',
                  ).create(recursive: true);
                  if (sensors.length == 1) {
                    final String filePath =
                        '${testDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
                    return SingleCaptureRequest(filePath, sensors.first);
                  }
                  return MultipleCaptureRequest({
                    for (final sensor in sensors)
                      sensor:
                          '${testDir.path}/${sensor.position == SensorPosition.front ? 'front_' : "back_"}${DateTime.now().millisecondsSinceEpoch}.jpg',
                  });
                },
              ),
              sensorConfig: SensorConfig.single(
                sensor: Sensor.position(SensorPosition.back),
                flashMode: FlashMode.auto,
                aspectRatio: CameraAspectRatios.ratio_4_3,
                zoom: 0.0,
              ),
              enablePhysicalButton: true,
              previewAlignment: Alignment.center,
              previewFit: CameraPreviewFit.contain,
              onMediaTap: (mediaCapture) {
                mediaCapture.captureRequest.when(
                  single: (single) {
                    final path = single.file?.path;
                    if (path != null) {
                      OpenFilex.open(path);
                    }
                  },
                  multiple: (multiple) {
                    multiple.fileBySensor.forEach((key, value) {
                      final path = value?.path;
                      if (path != null) {
                        OpenFilex.open(path);
                      }
                    });
                  },
                );
              },
              availableFilters: awesomePresetFiltersList,
              // Add bottom actions builder
              bottomActionsBuilder: (cameraState) {
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: 30,
                    left: 24,
                    right: 24,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Settings button
                      _IconButton(
                        icon: Icons.settings,
                        onTap: _navigateToSettings,
                        enabled: !_isCapturing,
                      ),

                      // Cool Capture Button - Using when() to access takePhoto()
                      cameraState.when(
                        onPhotoMode: (photoState) => _CaptureButton(
                          isCapturing: _isCapturing,
                          animationController: _captureAnimController,
                          scaleAnimation: _captureScaleAnimation,
                          onTap: () {
                            if (!_isCapturing) {
                              _captureAnimController.forward().then((_) {
                                _captureAnimController.reverse();
                              });
                              // Call takePhoto() on PhotoCameraState
                              photoState.takePhoto();
                            }
                          },
                        ),
                        onPreparingCamera: (state) => Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade800,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                        onVideoMode: (state) => const SizedBox.shrink(),
                        onVideoRecordingMode: (state) =>
                            const SizedBox.shrink(),
                        onPreviewMode: (state) => const SizedBox.shrink(),
                        onAnalysisOnlyMode: (state) => const SizedBox.shrink(),
                      ),

                      // Camera Switch Toggle Button
                      _CameraSwitchButton(
                        currentPosition: _currentCamera,
                        onTap: () {
                          if (!_isCapturing) {
                            // Toggle between front and back camera
                            final newPosition =
                                _currentCamera == SensorPosition.back
                                ? SensorPosition.front
                                : SensorPosition.back;

                            setState(() => _currentCamera = newPosition);

                            // Switch camera using the cameraState
                            cameraState.switchCameraSensor();
                          }
                        },
                        enabled: !_isCapturing,
                      ),
                      // Gallery thumbnail
                      _GalleryThumbnail(
                        latestThumbnail: _latestThumbnail,
                        onTap: _showGallery,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Cool Capture Button with animations and visual effects
class _CaptureButton extends StatelessWidget {
  final bool isCapturing;
  final AnimationController animationController;
  final Animation<double> scaleAnimation;
  final VoidCallback onTap;

  const _CaptureButton({
    required this.isCapturing,
    required this.animationController,
    required this.scaleAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isCapturing ? null : onTap,
      child: AnimatedBuilder(
        animation: animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: scaleAnimation.value,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: isCapturing
                      ? [Colors.grey.shade600, Colors.grey.shade800]
                      : [
                          Colors.white,
                          Colors.grey.shade200,
                          Colors.grey.shade400,
                        ],
                  stops: const [0.3, 0.7, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: isCapturing
                        ? Colors.black.withOpacity(0.5)
                        : Colors.white.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: isCapturing
                      ? Colors.grey.shade500
                      : Colors.white.withOpacity(0.8),
                  width: 4,
                ),
              ),
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isCapturing
                          ? [Colors.grey.shade700, Colors.grey.shade900]
                          : [const Color(0xFF667eea), const Color(0xFF764ba2)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isCapturing
                            ? Colors.transparent
                            : const Color(0xFF667eea).withOpacity(0.5),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: isCapturing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 32,
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Camera Switch Toggle Button
class _CameraSwitchButton extends StatelessWidget {
  final SensorPosition currentPosition;
  final VoidCallback onTap;
  final bool enabled;

  const _CameraSwitchButton({
    required this.currentPosition,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isBackCamera = currentPosition == SensorPosition.back;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? Colors.black.withOpacity(0.5)
              : Colors.grey.shade800.withOpacity(0.5),
          border: Border.all(
            color: enabled ? Colors.white.withOpacity(0.5) : Colors.white30,
            width: 2,
          ),
          boxShadow: [
            if (enabled)
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return RotationTransition(
                turns: animation,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: Icon(
              isBackCamera ? Icons.camera_rear : Icons.camera_front,
              key: ValueKey<bool>(isBackCamera),
              color: enabled ? Colors.white : Colors.white30,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

// Custom widget for gallery thumbnail
class _GalleryThumbnail extends StatelessWidget {
  final File? latestThumbnail;
  final VoidCallback onTap;

  const _GalleryThumbnail({required this.latestThumbnail, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasImages = latestThumbnail != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImages ? Colors.white.withOpacity(0.5) : Colors.white30,
            width: 2,
          ),
          color: Colors.black.withOpacity(0.3),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: hasImages
              ? Image.file(
                  latestThumbnail!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.photo_library, color: Colors.white, size: 24),
                )
              : Icon(Icons.photo_library, color: Colors.white30, size: 24),
        ),
      ),
    );
  }
}

// Custom icon button
class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  const _IconButton({
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        icon,
        color: enabled ? Colors.white : Colors.white30,
        size: 26,
      ),
      onPressed: enabled ? onTap : null,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }
}
