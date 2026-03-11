// lib/screens/camera_screen.dart

import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:sv_timestamp/l10n/app_localizations.dart';
import 'package:sv_timestamp/screens/SettingsScreen.dart';
import 'package:sv_timestamp/screens/gallery_screen.dart';
import 'package:vibration/vibration.dart';
import 'package:sv_timestamp/models/captured_image.dart';
import 'package:photo_manager/photo_manager.dart';
import '../utils/metadata_service.dart';
import '../utils/storage_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // Core
  late StorageService _storageService;
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isControllerInitialized = false;
  bool _isInitializing = false;

  // State
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _isLocationReady = false;
  String _cameraError = '';

  // Camera settings
  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.auto;

  // Zoom - FIXED: Better zoom management
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  bool _isZooming = false;
  double _baseZoom = 1.0;
  bool _zoomSupported = true;

  // Focus ring
  bool _showFocusRing = false;
  Offset _focusPosition = Offset.zero;
  late AnimationController _focusAnimation;
  Timer? _focusTimer;

  // Location
  Map<String, double>? _coords;
  String _address = "Loading...";

  // User settings
  late SharedPreferences _prefs;
  bool _soundOn = true;
  bool _vibrateOn = true;
  String _quality = 'High';
  double _watermarkSize = 25.0;

  // Animation
  late AnimationController _captureAnim;

  // Zoom debounce
  Timer? _zoomDebounceTimer;

  // Rotation handling
  bool _isDisposed = false;
  bool _isNavigatingAway = false;

  // Orientation
  Orientation _currentOrientation = Orientation.portrait;

  // Add a flag to track if camera is initializing
  bool _isCameraInitializing = false;

  // Track latest thumbnail from native gallery
  File? _latestThumbnail;

  // FIXED: Flag to track if we're switching cameras
  bool _isSwitchingCamera = false;

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
          if (a.name == 'SV-Watermark-Camera') {
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
          Directory('/storage/emulated/0/Pictures/SV-Watermark-Camera'),
          Directory('/storage/emulated/0/DCIM/SV-Watermark-Camera'),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _captureAnim = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _focusAnimation = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _init();
  }

  Future<void> _init() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      await _loadPrefs();
      await _initLocation();
      await _initCamera();
      await _loadLatestThumbnail();
    } catch (e) {
      print('Init error: $e');
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    if (_isDisposed) return;

    setState(() {
      _soundOn = _prefs.getBool('sound_on_capture') ?? true;
      _vibrateOn = _prefs.getBool('vibration_on_capture') ?? true;
      _quality = _prefs.getString('image_quality') ?? 'High';
      _watermarkSize = _prefs.getDouble('watermark_size') ?? 25.0;

      final title = _prefs.getString('app_title');
      if (title?.isNotEmpty == true) MetadataService.setAppTitle(title!);

      final logoPath = _prefs.getString('custom_logo_path');
      if (logoPath != null) MetadataService.setCustomLogoPath(logoPath);
    });
  }

  Future<void> _initLocation() async {
    try {
      final loc = await MetadataService.getCurrentLocation();
      if (_isDisposed) return;

      if (loc != null && mounted) {
        final addr = await MetadataService.getAddressFromCoordinates(
          loc['latitude']!,
          loc['longitude']!,
        );
        setState(() {
          _coords = loc;
          _address = addr ?? "Unknown";
          _isLocationReady = true;
        });
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

  Future<void> _initCamera() async {
    if (_isDisposed || _isNavigatingAway || _isCameraInitializing) return;

    _isCameraInitializing = true;

    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraError = 'No cameras found';
            _isCameraReady = false;
          });
        }
        return;
      }

      _cameraIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      if (_cameraIndex == -1) _cameraIndex = 0;

      await _disposeController();

      // FIXED: Reset zoom to safe defaults before creating controller
      _zoom = 1.0;
      _baseZoom = 1.0;
      _minZoom = 1.0;
      _maxZoom = 1.0;
      _zoomSupported = true;

      _controller = CameraController(
        _cameras[_cameraIndex],
        _getResolution(),
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      // Add listener before initialization
      _controller!.addListener(_onCameraControllerListener);

      await _controller!.initialize();

      if (_isDisposed || _isNavigatingAway) {
        await _disposeController();
        return;
      }

      _isControllerInitialized = true;

      // FIXED: Configure zoom after camera is initialized
      await _configureZoom();

      await _configureCamera();

      if (mounted && !_isDisposed && !_isNavigatingAway) {
        setState(() {
          _isCameraReady = true;
          _cameraError = '';
          _isSwitchingCamera = false;
        });
      }
    } on CameraException catch (e) {
      print('CameraException: ${e.code} - ${e.description}');
      _handleCameraError('Camera error: ${e.description}');
    } catch (e) {
      print('Camera init error: $e');
      _handleCameraError('Camera initialization failed: $e');
    } finally {
      _isCameraInitializing = false;
    }
  }

  // FIXED: Separate method for zoom configuration
  Future<void> _configureZoom() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();

      // Ensure zoom values are valid
      if (_minZoom < 1.0) _minZoom = 1.0;
      if (_maxZoom < _minZoom) _maxZoom = _minZoom;

      _zoom = _minZoom;
      _baseZoom = _minZoom;

      // Set initial zoom level
      await _controller!.setZoomLevel(_zoom);
      _zoomSupported = true;

      print('Zoom configured: min=$_minZoom, max=$_maxZoom, current=$_zoom');
    } catch (e) {
      print('Zoom not supported on this camera: $e');
      _zoomSupported = false;
      _minZoom = 1.0;
      _maxZoom = 1.0;
      _zoom = 1.0;
      _baseZoom = 1.0;
    }
  }

  void _onCameraControllerListener() {
    if (_isDisposed || _isNavigatingAway || !mounted || _controller == null)
      return;

    if (_controller!.value.hasError) {
      _handleCameraError(
        'Camera error: ${_controller!.value.errorDescription}',
      );
    }
  }

  void _handleCameraError(String error) {
    if (mounted && !_isDisposed && !_isNavigatingAway) {
      setState(() {
        _cameraError = error;
        _isCameraReady = false;
        _isSwitchingCamera = false;
      });
    }
  }

  Future<void> _configureCamera() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setExposureMode(ExposureMode.auto);
      await _controller!.setFlashMode(_flashMode);
    } catch (e) {
      print('Camera configuration error: $e');
    }
  }

  Future<void> _disposeController() async {
    if (_controller != null) {
      // Remove listener first
      try {
        _controller!.removeListener(_onCameraControllerListener);
      } catch (e) {
        print('Error removing listener: $e');
      }

      try {
        await _controller!.dispose();
      } catch (e) {
        print('Error disposing controller: $e');
      }
      _controller = null;
      _isControllerInitialized = false;
      _isCameraReady = false;
    }
  }

  ResolutionPreset _getResolution() {
    switch (_quality) {
      case 'Low':
        return ResolutionPreset.medium;
      case 'Medium':
        return ResolutionPreset.high;
      case 'Ultra':
        return ResolutionPreset.max;
      case 'High':
      default:
        return ResolutionPreset.veryHigh;
    }
  }

  bool _canTakePicture() {
    return _controller != null &&
        _controller!.value.isInitialized &&
        !_isCapturing &&
        _isControllerInitialized &&
        _isCameraReady &&
        !_isDisposed &&
        !_isNavigatingAway &&
        !_isSwitchingCamera;
  }

  Future<void> _saveToDeviceGallery(File image) async {
    try {
      // Ensure the file exists and is readable
      if (!await image.exists()) {
        print('File does not exist: ${image.path}');
        return;
      }

      // Wait a tiny bit to ensure file is fully written
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify we can read the file
      final fileStat = await image.stat();
      print('File size: ${fileStat.size} bytes');

      if (fileStat.size == 0) {
        print('File is empty');
        return;
      }

      // Save to device gallery
      final result = await GallerySaver.saveImage(
        image.path,
        albumName: 'SV-Watermark-Camera',
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
      // Don't show error to user - it's not critical
    }
  }

  Future<void> _takePicture() async {
    if (!_canTakePicture()) return;

    // Add a safety check for controller
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
    } catch (e) {
      print('Focus/Exposure error: $e');
    }

    _captureAnim.forward();
    setState(() => _isCapturing = true);

    if (_soundOn) {
      SystemSound.play(SystemSoundType.click);
    }

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
      // Take picture
      final image = await controller.takePicture();

      // Create temp file
      final tempDir = await getTemporaryDirectory();
      final tempPath = path.join(
        tempDir.path,
        'temp_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      await File(image.path).rename(tempPath);

      final timestamp = DateTime.now();
      final loc = mounted ? AppLocalizations.of(context) : null;

      // Read image bytes
      final imageBytes = await File(tempPath).readAsBytes();

      // Add metadata watermark
      final processed = await MetadataService.addMetadataToImage(
        imageBytes,
        timestamp,
        _coords,
        _address,
        locationLabel: loc?.locationLabel ?? 'Location:',
        addressLabel: loc?.addressLabel ?? 'Address:',
        datetimeLabel: loc?.datetimeLabel ?? 'Date:',
      );

      // Create final file in temporary directory first
      final finalTempPath = path.join(
        tempDir.path,
        'watermarked_${timestamp.millisecondsSinceEpoch}.jpg',
      );
      await File(finalTempPath).writeAsBytes(processed);

      // Clean up temp files
      if (await File(tempPath).exists()) {
        await File(tempPath).delete();
      }

      // Update storage service for gallery thumbnails
      _storageService.capturedImages.insert(
        0,
        CapturedImage(
          id: timestamp.millisecondsSinceEpoch.toString(),
          imagePath: finalTempPath,
          timestamp: timestamp,
          location: _coords,
          address: _address,
          additionalData: {
            'quality': _quality,
            'zoom': _zoom.toStringAsFixed(1),
            'flash': _flashMode.toString(),
          },
        ),
      );

      // Verify file was written
      final finalFile = File(finalTempPath);
      if (await finalFile.exists()) {
        print('Watermarked image created: ${finalFile.path}');

        // Save directly to device gallery
        await _saveToDeviceGallery(finalFile);

        // Immediately update thumbnail for instant UI gratification
        if (mounted) {
          setState(() {
            _latestThumbnail = finalFile;
          });
        }

        // Refresh thumbnail reliably in the background
        Future.delayed(const Duration(seconds: 2), _loadLatestThumbnail);
      }
    } catch (e) {
      print('Capture error: $e');
      if (mounted) {
        final errorMsg = e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed: ${errorMsg.substring(0, min(50, errorMsg.length))}',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        _captureAnim.reverse();
        setState(() => _isCapturing = false);
      }
    }
  }

  // Add this helper method to safely access the controller
  CameraController? _getSafeController() {
    if (_controller != null &&
        _controller!.value.isInitialized &&
        !_isDisposed &&
        !_isNavigatingAway &&
        !_isSwitchingCamera) {
      return _controller;
    }
    return null;
  }

  // FIXED: Improved camera switching with proper zoom reset
  Future<void> _switchCamera() async {
    if (_cameras.length < 2 ||
        _isCapturing ||
        _isCameraInitializing ||
        _isSwitchingCamera)
      return;

    _isSwitchingCamera = true;
    _zoomDebounceTimer?.cancel();

    // Update UI to show loading state
    setState(() {
      _isCameraReady = false;
      _isControllerInitialized = false;
      _isZooming = false;
      _zoom = 1.0;
      _baseZoom = 1.0;
      _minZoom = 1.0;
      _maxZoom = 1.0;
    });

    try {
      await _disposeController();

      _cameraIndex = (_cameraIndex + 1) % _cameras.length;

      _controller = CameraController(
        _cameras[_cameraIndex],
        _getResolution(),
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      // Add listener before initialization
      _controller!.addListener(_onCameraControllerListener);

      await _controller!.initialize();

      if (_isDisposed || _isNavigatingAway) {
        await _disposeController();
        return;
      }

      _isControllerInitialized = true;

      // FIXED: Configure zoom after initialization
      await _configureZoom();

      // Configure other camera settings
      await _configureCamera();

      if (mounted && !_isDisposed && !_isNavigatingAway) {
        setState(() {
          _isCameraReady = true;
          _cameraError = '';
          _isSwitchingCamera = false;
        });
      }
    } catch (e) {
      print('Switch camera error: $e');
      if (mounted && !_isDisposed && !_isNavigatingAway) {
        setState(() {
          _cameraError = 'Failed to switch camera: $e';
          _isCameraReady = false;
          _isSwitchingCamera = false;
        });
      }
    }
  }

  void _toggleFlash() async {
    final controller = _getSafeController();
    if (controller == null) return;

    try {
      const modes = [
        FlashMode.off,
        FlashMode.auto,
        FlashMode.always,
        FlashMode.torch,
      ];
      final currentIndex = modes.indexOf(_flashMode);
      final nextIndex = (currentIndex + 1) % modes.length;
      final newMode = modes[nextIndex];

      await controller.setFlashMode(newMode);
      if (mounted) setState(() => _flashMode = newMode);
    } catch (e) {
      print('Flash error: $e');
    }
  }

  bool _canInteractWithCamera() {
    return _controller != null &&
        _controller!.value.isInitialized &&
        _isCameraReady &&
        !_isCapturing &&
        !_isDisposed &&
        !_isNavigatingAway &&
        !_isSwitchingCamera;
  }

  // FIXED: Improved zoom handling with better safety checks
  void _onScaleStart(ScaleStartDetails details) {
    if (!_canInteractWithCamera() || !_zoomSupported) return;
    _baseZoom = _zoom;
    setState(() => _isZooming = true);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) async {
    if (!_canInteractWithCamera() || !_zoomSupported) return;

    final controller = _getSafeController();
    if (controller == null) return;

    try {
      // Calculate new zoom with safety bounds
      double zoom = _baseZoom * details.scale;
      zoom = zoom.clamp(_minZoom, _maxZoom);

      // Only update if change is significant
      if ((zoom - _zoom).abs() > 0.01) {
        await controller.setZoomLevel(zoom);
        if (mounted && !_isDisposed) {
          setState(() => _zoom = zoom);
        }
      }
    } catch (e) {
      print('Zoom error: $e');
      setState(() => _isZooming = false);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (mounted) setState(() => _isZooming = false);
  }

  void _onFocusTap(TapUpDetails details) {
    final controller = _getSafeController();
    if (controller == null) return;

    final box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(details.globalPosition);
    final size = box.size;

    double x = (localPosition.dx / size.width).clamp(0.0, 1.0);
    double y = (localPosition.dy / size.height).clamp(0.0, 1.0);

    setState(() {
      _showFocusRing = true;
      _focusPosition = localPosition;
    });

    _focusAnimation.forward(from: 0.0);

    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _showFocusRing = false);
    });

    try {
      controller.setFocusPoint(Offset(x, y));
      controller.setExposurePoint(Offset(x, y));
    } catch (e) {
      print('Focus error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    _storageService = Provider.of<StorageService>(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: OrientationBuilder(
        builder: (context, orientation) {
          _currentOrientation = orientation;
          return _buildBody();
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_cameraError.isNotEmpty && !_isCameraReady) {
      return _buildError();
    }

    return _buildCamera();
  }

  Widget _buildCamera() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPreview(),
        if (_showFocusRing)
          Positioned(
            left: _focusPosition.dx - 40,
            top: _focusPosition.dy - 40,
            child: AnimatedBuilder(
              animation: _focusAnimation,
              builder: (_, __) => Opacity(
                opacity: 1 - _focusAnimation.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.amber, width: 2),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        SafeArea(
          child: _currentOrientation == Orientation.portrait
              ? _buildPortraitUI()
              : _buildLandscapeUI(),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    // Safe check for controller and initialization
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        !_isCameraReady ||
        _isCameraInitializing ||
        _isSwitchingCamera) {
      return _buildLoading();
    }

    // Full-screen camera preview with proper scaling
    return GestureDetector(
      onTapUp: _onFocusTap,
      onScaleStart: _zoomSupported ? _onScaleStart : null,
      onScaleUpdate: _zoomSupported ? _onScaleUpdate : null,
      onScaleEnd: _zoomSupported ? _onScaleEnd : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: CameraPreview(_controller!),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 20),
            Text(
              _isSwitchingCamera
                  ? 'Switching camera...'
                  : (_isCameraInitializing
                        ? 'Initializing camera...'
                        : 'Loading camera...'),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // Modern iOS-style frosted glass top bar
  Widget _buildTopBar() {
    final canInteract = _canInteractWithCamera();

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _flashButton(),
              const SizedBox(width: 16),
              _iconButton(
                Icons.cameraswitch_outlined,
                _switchCamera,
                enabled:
                    _cameras.length > 1 &&
                    !_isCapturing &&
                    !_isCameraInitializing &&
                    !_isSwitchingCamera,
              ),
              const SizedBox(width: 16),
              _iconButton(
                Icons.settings_outlined,
                _navigateToSettings,
                enabled:
                    !_isCapturing &&
                    !_isCameraInitializing &&
                    !_isSwitchingCamera,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Flash button with "Auto" label when in auto mode
  Widget _flashButton() {
    final isAuto = _flashMode == FlashMode.auto;
    final canInteract = _canInteractWithCamera();

    return GestureDetector(
      onTap: canInteract ? _toggleFlash : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: isAuto
            ? BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _flashIcon,
              color: canInteract ? Colors.white : Colors.white30,
              size: 22,
            ),
            if (isAuto) ...[
              const SizedBox(width: 4),
              Text(
                'Auto',
                style: TextStyle(
                  color: canInteract ? Colors.white : Colors.white30,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Modern iOS-style frosted glass bottom panel
  Widget _buildBottomPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.2), width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _galleryThumb(),
                _captureButton(),
                _iconButton(
                  Icons.brush_outlined,
                  _showWatermarkSettings,
                  enabled:
                      !_isCapturing &&
                      !_isCameraInitializing &&
                      !_isSwitchingCamera,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Top bar with frosted glass effect
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
          child: Align(alignment: Alignment.topCenter, child: _buildTopBar()),
        ),

        if (_isZooming && _zoomSupported) Center(child: _buildZoomIndicator()),

        // Bottom frosted panel
        _buildBottomPanel(),
      ],
    );
  }

  Widget _buildLandscapeUI() {
    return NativeDeviceOrientedWidget(
      useSensor: true,
      portraitUp: (context) => _buildOrientedUI(0),
      portraitDown: (context) => _buildOrientedUI(2),
      landscapeLeft: (context) => _buildOrientedUI(3),
      landscapeRight: (context) => _buildOrientedUI(1),
      fallback: (context) => _buildOrientedUI(0),
    );
  }

  Widget _buildOrientedUI(int quarterTurns) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
      child: RotatedBox(
        quarterTurns: quarterTurns,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
              child: Align(
                alignment: Alignment.topCenter,
                child: _buildTopBar(),
              ),
            ),
            if (_isZooming && _zoomSupported)
              Center(child: _buildZoomIndicator()),
            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off_rounded;
      case FlashMode.auto:
        return Icons.flash_on_rounded;
      case FlashMode.torch:
        return Icons.flashlight_on_rounded;
      default:
        return Icons.flash_on_rounded;
    }
  }

  Widget _buildZoomIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${_zoom.toStringAsFixed(1)}x',
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }

  Widget _galleryThumb() {
    final hasImages = _latestThumbnail != null;

    return GestureDetector(
      onTap: _showGallery, // Always allow tapping to view gallery
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
                  _latestThumbnail!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.photo_library, color: Colors.white, size: 24),
                )
              : Icon(Icons.photo_library, color: Colors.white30, size: 24),
        ),
      ),
    );
  }

  // Modern iOS-style capture button with white ring and solid center
  Widget _captureButton() {
    final canCapture = _canTakePicture();

    return AnimatedBuilder(
      animation: _captureAnim,
      builder: (_, __) => Transform.scale(
        scale: 1 - (_captureAnim.value * 0.1),
        child: GestureDetector(
          onTap: canCapture ? _takePicture : null,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: canCapture ? Colors.white : Colors.white30,
                width: 4,
              ),
            ),
            child: Center(
              child: _isCapturing
                  ? SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                        strokeWidth: 3,
                        backgroundColor: Colors.transparent,
                      ),
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: canCapture ? Colors.white : Colors.white30,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap, {bool enabled = true}) {
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

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(
            _cameraError,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _cameraError = '';
                _isCameraReady = false;
              });
              _initCamera();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _navigateToSettings() async {
    if (_isNavigatingAway || _isCapturing || _isSwitchingCamera) return;

    _isNavigatingAway = true;

    // Dispose first, then navigate
    await _disposeController();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );

    if (mounted) {
      _isNavigatingAway = false;
      await _loadPrefs();
      await _initCamera();
    }
  }

  void _showWatermarkSettings() {
    if (!mounted || _isCapturing || _isSwitchingCamera) return;

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
                      _prefs.setDouble('watermark_size', tempSize);
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

  void _showGallery() async {
    if (_isNavigatingAway || _isSwitchingCamera) return;

    _isNavigatingAway = true;
    await _disposeController();

    if (!mounted) return;

    // Navigate to GalleryScreen
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GalleryScreen()),
    );

    if (mounted) {
      _isNavigatingAway = false;
      await _initCamera();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _captureAnim.dispose();
    _focusAnimation.dispose();
    _zoomDebounceTimer?.cancel();
    _focusTimer?.cancel();
    _disposeController();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || _isNavigatingAway) return;

    switch (state) {
      case AppLifecycleState.resumed:
        if (_controller == null || !_controller!.value.isInitialized) {
          _initCamera();
        }
        _loadLatestThumbnail();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (!_isNavigatingAway) {
          _disposeController();
        }
        break;
    }
  }
}
