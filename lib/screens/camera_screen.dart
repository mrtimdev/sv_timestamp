import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sv_timestamp/l10n/app_localizations.dart';
import 'package:sv_timestamp/screens/SettingsScreen.dart';
import 'package:sv_timestamp/screens/full_screen_image_viewer.dart';
import 'package:sv_timestamp/utils/setting_provider.dart';
import 'package:sv_timestamp/widgets/setting_item.dart';
import 'package:vibration/vibration.dart';
import 'package:sv_timestamp/models/captured_image.dart';
import '../utils/metadata_service.dart';
import '../utils/storage_service.dart';
import '../widgets/image_card.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  SharedPreferences? _prefs;
  CameraController? _controller;
  late StorageService _storageService;
  late List<CameraDescription> _cameras;
  String _currentAddress = "Loading...";
  Map<String, double>? _currentCoords;
  bool _showLocation = true;
  bool _isCapturing = false;
  bool _isCameraReady = false;
  bool _isLocationReady = false;
  double _currentZoom = 1.0;
  FlashMode _currentFlash = FlashMode.off;
  int _currentCameraIndex = 0;

  // New settings from SettingsScreen
  bool _showGrid = false;
  bool _soundOnCapture = true;
  bool _vibrationOnCapture = true;
  String _imageQuality = 'High';
  String _watermarkPosition = 'Bottom Right';
  double _watermarkOpacity = 0.8;
  double _watermarkSize = 25.0;
  bool _isFlashSupported = true;
  bool _isZoomSupported = true;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 10.0;
  bool _isZooming = false;
  OverlayEntry? _zoomOverlay;

  double _baseZoomLevel = 1.0;
  double _scaleZoom = 1.0;

  // Animation controllers
  late AnimationController _captureAnimationController;
  late AnimationController _flashAnimationController;
  late Animation<double> _captureAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize animation controllers
    _captureAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _flashAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _captureAnimation = Tween<double>(begin: 1.0, end: 0.7).animate(
      CurvedAnimation(
        parent: _captureAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _initApp();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _storageService = Provider.of<StorageService>(context, listen: false);
  }

  Future<void> _initApp() async {
    await _loadSettings();
    await MetadataService.initEmojiCache();

    await _initLocation();
    await _initializeCamera();
  }

  // Add this method to load settings
  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();

    // Load settings from SharedPreferences
    setState(() {
      _soundOnCapture = _prefs?.getBool('sound_on_capture') ?? true;
      _vibrationOnCapture = _prefs?.getBool('vibration_on_capture') ?? true;
      _imageQuality = _prefs?.getString('image_quality') ?? 'High';
      _watermarkPosition =
          _prefs?.getString('watermark_position') ?? 'Bottom Right';
      _watermarkOpacity = _prefs?.getDouble('watermark_opacity') ?? 0.8;
      _watermarkSize = _prefs?.getDouble('watermark_size') ?? 25.0;

      // Load app title and custom logo
      final customTitle = _prefs?.getString('app_title');
      if (customTitle != null && customTitle.isNotEmpty) {
        MetadataService.setAppTitle(customTitle);
      }

      final customLogoPath = _prefs?.getString('custom_logo_path');
      if (customLogoPath != null) {
        MetadataService.setCustomLogoPath(customLogoPath);
      }
    });
  }

  Future<void> _initLocation() async {
    try {
      final loc = await MetadataService.getCurrentLocation();
      final locale = context.read<SettingsProvider>().currentLocale;
      if (loc != null) {
        final addr = await MetadataService.getAddressFromCoordinates(
          loc['latitude']!,
          loc['longitude']!,
          // locale,
        );
        if (mounted) {
          setState(() {
            _currentCoords = loc;
            _currentAddress = addr ?? "Unknown Location";
            _isLocationReady = true;
          });
        }
      } else if (mounted) {
        setState(() {
          _currentAddress = "Location not available";
          _isLocationReady = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentAddress = "Location error";
          _isLocationReady = true;
        });
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No cameras found');
      }

      _controller = CameraController(
        _cameras[_currentCameraIndex],
        _getResolutionFromQuality(),
        enableAudio: false,
      );

      await _controller!.initialize();

      if (_isZoomSupported) {
        _minZoomLevel = await _controller!.getMinZoomLevel();
        _maxZoomLevel = await _controller!.getMaxZoomLevel();
        _currentZoom = _minZoomLevel;
        await _controller!.setZoomLevel(_currentZoom);
      }

      if (mounted) {
        setState(() {
          _isCameraReady = true;
        });
      }
    } catch (e) {
      print('Camera initialization error: $e');
      if (mounted) {
        _showErrorDialog('Camera Error', e.toString());
      }
    }
  }

  ResolutionPreset _getResolutionFromQuality() {
    switch (_imageQuality) {
      case 'Low':
        return ResolutionPreset.low;
      case 'Medium':
        return ResolutionPreset.medium;
      case 'Ultra':
        return ResolutionPreset.veryHigh;
      case 'High':
      default:
        return ResolutionPreset.high;
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;

    setState(() {
      _isCameraReady = false;
    });

    await _controller!.dispose();

    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;

    _controller = CameraController(
      _cameras[_currentCameraIndex],
      _getResolutionFromQuality(),
      enableAudio: false,
    );

    await _controller!.initialize();

    if (mounted) {
      setState(() {
        _isCameraReady = true;
      });
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;

    final modes = [FlashMode.off, FlashMode.auto, FlashMode.always];
    final currentIndex = modes.indexOf(_currentFlash);
    final nextIndex = (currentIndex + 1) % modes.length;

    try {
      await _controller!.setFlashMode(modes[nextIndex]);
      if (mounted) {
        setState(() {
          _currentFlash = modes[nextIndex];
        });
      }
    } catch (e) {
      print('Error setting flash: $e');
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    // Start capture animation
    _captureAnimationController.forward();

    setState(() {
      _isCapturing = true;
    });

    // Play sound if enabled
    if (_soundOnCapture) {
      SystemSound.play(SystemSoundType.click);
    }

    // Vibrate if enabled
    if (_vibrationOnCapture && await Vibration.hasVibrator() == true) {
      Vibration.vibrate(duration: 50);
    }

    try {
      // Capture image
      final image = await _controller!.takePicture();

      // Create temporary file path
      final tempDir = await getTemporaryDirectory();
      final tempPath = path.join(
        tempDir.path,
        'temp_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      // Move to temp location
      await File(image.path).copy(tempPath);

      // Prepare metadata
      final timestamp = DateTime.now();

      // Process in background
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          // Read image bytes
          final originalBytes = await File(tempPath).readAsBytes();

          final loc = AppLocalizations.of(context);

          String test = loc!.addressLabel;
          print("test: $test");
          // Process with MetadataService
          final processedBytes = await MetadataService.addMetadataToImage(
            originalBytes,
            timestamp,
            _currentCoords,
            _showLocation ? _currentAddress : null,
            locationLabel: loc.locationLabel,
            addressLabel: loc.addressLabel,
            datetimeLabel: loc.datetimeLabel,
          );

          // Create captured image object
          final appDir = await getApplicationDocumentsDirectory();
          final fileName = '${timestamp.millisecondsSinceEpoch}.jpg';
          final savedPath = path.join(appDir.path, 'captured_images', fileName);

          // Ensure directory exists
          await Directory(path.dirname(savedPath)).create(recursive: true);

          // Save processed image
          await File(savedPath).writeAsBytes(processedBytes);

          // Create and add to storage
          final capturedImage = CapturedImage(
            id: timestamp.millisecondsSinceEpoch.toString(),
            imagePath: savedPath,
            timestamp: timestamp,
            location: _currentCoords,
            address: _showLocation ? _currentAddress : null,
            additionalData: {
              'device': 'Mobile',
              'app': 'SV',
              'flash': _currentFlash.toString(),
              'camera': _cameras[_currentCameraIndex].lensDirection.toString(),
              'quality': _imageQuality,
              'zoom': _currentZoom.toStringAsFixed(1),
            },
          );

          _storageService.capturedImages.insert(0, capturedImage);

          // Clean up temp file
          await File(tempPath).delete();

          if (mounted) {
            // Show success
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Image captured successfully!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          print('Error processing image: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } finally {
          if (mounted) {
            _captureAnimationController.reverse();
            setState(() {
              _isCapturing = false;
            });
          }
        }
      });
    } catch (e) {
      print('Capture error: $e');
      if (mounted) {
        _captureAnimationController.reverse();
        setState(() {
          _isCapturing = false;
        });
        _showErrorDialog('Capture Failed', e.toString());
      }
    }
  }

  Widget _buildCameraView() {
    return Stack(
      children: [
        Positioned.fill(
          child: _controller != null && _controller!.value.isInitialized
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,

                  onScaleStart: (details) {
                    _baseZoomLevel = _currentZoom;
                  },

                  onScaleUpdate: (details) async {
                    if (!_isZoomSupported) return;

                    _scaleZoom = (_baseZoomLevel * details.scale).clamp(
                      _minZoomLevel,
                      _maxZoomLevel,
                    );

                    if (_scaleZoom != _currentZoom) {
                      _currentZoom = _scaleZoom;
                      await _controller?.setZoomLevel(_currentZoom);

                      if (mounted) {
                        setState(() {});
                      }
                    }
                  },

                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.previewSize!.height,
                      height: _controller!.value.previewSize!.width,
                      child: CameraPreview(_controller!),
                    ),
                  ),
                )
              : Container(color: Colors.black),
        ),

        // Top Controls
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 0,
          right: 0,
          child: _buildTopControls(),
        ),

        // Watermark Overlay
        //_buildPositionedWatermark(),

        // Flash animation overlay
        if (_flashAnimationController.isAnimating)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _flashAnimationController,
              builder: (context, child) {
                return Container(
                  color: Colors.white.withOpacity(
                    _flashAnimationController.value * 0.7,
                  ),
                );
              },
            ),
          ),

        // Bottom Controls
        Positioned(
          bottom: 30,
          left: 0,
          right: 0,
          child: _buildCameraControls(),
        ),

        // Zoom slider overlay
        if (_isZooming) _buildZoomOverlay(),
      ],
    );
  }

  Widget _buildTopControls() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Flash Button
            IconButton(
              icon: Icon(
                _currentFlash == FlashMode.off
                    ? Icons.flash_off
                    : _currentFlash == FlashMode.auto
                    ? Icons.flash_auto
                    : Icons.flash_on,
                color: Colors.white,
                size: 28,
              ),
              onPressed: _toggleFlash,
            ),
            // Switch Camera
            IconButton(
              icon: const Icon(
                Icons.cameraswitch,
                color: Colors.white,
                size: 28,
              ),
              onPressed: _cameras.length > 1 ? _switchCamera : null,
              tooltip: 'Switch camera',
            ),

            // Settings button
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white, size: 28),
              onPressed: _navigateToSettings,
              tooltip: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomOverlay() {
    // Hide slider if zoom not supported or no range
    if (!_isZoomSupported || (_minZoomLevel == _maxZoomLevel))
      return SizedBox.shrink();

    // Use divisions only if range > 0.1
    final double range = _maxZoomLevel - _minZoomLevel;
    final int? divisions = range > 0.1 ? (range * 10).toInt() : null;

    return Positioned(
      right: 20,
      top: MediaQuery.of(context).size.height / 2 - 100,
      child: Container(
        width: 60,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(30),
        ),
        child: RotatedBox(
          quarterTurns: 3,
          child: Slider(
            value: _currentZoom.clamp(_minZoomLevel, _maxZoomLevel),
            min: _minZoomLevel,
            max: _maxZoomLevel,
            divisions: divisions,
            activeColor: Colors.white,
            inactiveColor: Colors.grey,
            onChangeStart: (_) {
              setState(() => _isZooming = true);
            },
            onChanged: (value) {
              // Update slider thumb immediately
              setState(() {
                _currentZoom = value.clamp(_minZoomLevel, _maxZoomLevel);
              });
            },
            onChangeEnd: (value) async {
              final zoomValue = value.clamp(_minZoomLevel, _maxZoomLevel);
              try {
                // Only call async zoom after user finishes dragging
                await _controller?.setZoomLevel(zoomValue);
              } catch (e) {
                print("Zoom error: $e");
              }

              // Hide overlay after a short delay
              Future.delayed(
                const Duration(milliseconds: 500),
                () => setState(() => _isZooming = false),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCameraControls() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Gallery button
            GestureDetector(
              onTap: _showGalleryPreview,
              child: _storageService.capturedImages.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_storageService.capturedImages.first.imagePath),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          // fallback to icon if image fails
                          return const Icon(
                            Icons.photo_library,
                            color: Colors.white,
                            size: 32,
                          );
                        },
                      ),
                    )
                  : const Icon(
                      Icons.photo_library,
                      color: Colors.white,
                      size: 32,
                    ),
            ),

            // Capture Button
            AnimatedBuilder(
              animation: _captureAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _captureAnimation.value,
                  child: _buildCaptureButton(),
                );
              },
            ),

            // Watermark customization
            IconButton(
              icon: const Icon(Icons.brush, color: Colors.white, size: 32),
              onPressed: _showWatermarkCustomization,
              tooltip: 'Customize watermark',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _isCapturing ? null : _takePicture,
      child: Container(
        height: 80,
        width: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(
            color: _isCapturing ? Colors.grey : Colors.white,
            width: _isCapturing ? 3 : 5,
          ),
          boxShadow: [
            BoxShadow(
              color: _isCapturing
                  ? Colors.grey.withOpacity(0.5)
                  : Colors.white.withOpacity(0.3),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: _isCapturing
              ? CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  strokeWidth: 3,
                )
              : Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.all(8),
                  ),
                ),
        ),
      ),
    );
  }

  void _navigateToSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );

    // Reload settings when returning from settings screen
    if (mounted) {
      // Reinitialize camera with new quality settings if needed
      if (_controller != null && _controller!.value.isInitialized) {
        await _controller!.dispose();
        await _initializeCamera();
      }

      // Reload settings directly from SharedPreferences
      await _reloadSettingsFromPrefs();
    }
  }

  Future<void> _reloadSettingsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _soundOnCapture = prefs.getBool('sound_on_capture') ?? true;
      _vibrationOnCapture = prefs.getBool('vibration_on_capture') ?? true;
      _imageQuality = prefs.getString('image_quality') ?? 'High';
      _watermarkOpacity = prefs.getDouble('watermark_opacity') ?? 0.8;
      _watermarkSize = prefs.getDouble('watermark_size') ?? 25.0;
    });
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showGalleryPreview() {
    if (_storageService.capturedImages.isNotEmpty) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => _buildGalleryPreview(),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No photos yet. Capture some first!'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Widget _buildGalleryPreview() {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recent Photos',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Close',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
              // Images grid
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _storageService.capturedImages.length,
                  itemBuilder: (context, index) {
                    final image = _storageService.capturedImages[index];
                    return GestureDetector(
                      onTap: () => _showFullImage(image),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(image.imagePath),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey,
                              child: const Icon(Icons.error),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFullImage(CapturedImage image) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImageViewer(image: image),
      ),
    );
  }

  void _showWatermarkCustomization() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Container(
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Customize Watermark',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.text_fields, color: Colors.white),
                  const SizedBox(width: 10),
                  const Text(
                    'Text Size:',
                    style: TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    '${_watermarkSize.toInt()}px',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              Slider(
                value: _watermarkSize,
                min: 20.0,
                max: 100.0,
                // divisions: 6,
                label: '${_watermarkSize.toInt()}px',
                onChanged: (value) => setState(() => _watermarkSize = value),
                onChangeEnd: (value) => _saveSetting('watermark_size', value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveSetting<T>(String key, T value) async {
    final _prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await _prefs.setBool(key, value);
    } else if (value is String) {
      await _prefs.setString(key, value);
    } else if (value is double) {
      await _prefs.setDouble(key, value);
    } else if (value is int) {
      await _prefs.setInt(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isCameraReady
          ? _buildCameraView()
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text(
                    'Initializing camera...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureAnimationController.dispose();
    _flashAnimationController.dispose();
    _controller?.dispose();
    _zoomOverlay?.remove();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller != null && !_controller!.value.isInitialized) {
        _initializeCamera();
      }
    }
  }
}
