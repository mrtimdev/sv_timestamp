// lib/screens/cool_camera_screen.dart

import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';

// Update these imports based on your actual project structure
import 'package:sv_timestamp/l10n/app_localizations.dart';
import 'package:sv_timestamp/models/captured_image.dart';
import '../utils/metadata_service.dart';
import '../utils/storage_service.dart';

class CoolCameraScreen extends StatefulWidget {
  const CoolCameraScreen({super.key});

  @override
  State<CoolCameraScreen> createState() => _CoolCameraScreenState();
}

class _CoolCameraScreenState extends State<CoolCameraScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Camera Core
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraReady = false;
  String _cameraError = '';
  bool _isInitialized = false;
  bool _isLoading = true; // Add loading state

  // Camera Settings
  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  double _zoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 10.0;

  // Location
  Map<String, double>? _coordinates;
  String _locationAddress = "Unknown";
  bool _isLocationReady = false;

  // User Settings
  bool _soundOn = true;
  bool _vibrateOn = true;
  String _quality = 'High';
  double _watermarkSize = 25.0;

  // UI State
  bool _isCapturing = false;
  bool _showFocusRing = false;
  Offset _focusPosition = Offset.zero;
  double _currentZoom = 1.0;

  // Animations
  late AnimationController _shutterAnimation;
  late AnimationController _focusAnimation;
  late AnimationController _zoomIndicatorAnimation;
  late AnimationController _gridAnimation;
  late AnimationController _captureAnimation;

  // Grid overlay
  bool _showGrid = false;

  // Zoom tracking
  double _baseZoom = 1.0;
  Timer? _zoomDebounceTimer;

  // Focus tracking
  Timer? _focusTimer;

  // Lifecycle
  bool _isDisposed = false;

  // Cool UI colors
  final Color _primaryBlue = const Color(0xFF4158D0);
  final Color _primaryPurple = const Color(0xFFC850C0);
  final Color _primaryOrange = const Color(0xFFFFCC70);

  @override
  void initState() {
    super.initState();
    print('🔵 CoolCameraScreen initState');
    WidgetsBinding.instance.addObserver(this);

    // Initialize animations
    _shutterAnimation = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _focusAnimation = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _zoomIndicatorAnimation = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _gridAnimation = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _captureAnimation = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Initialize camera
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('🔵 App lifecycle state: $state');
    final CameraController? cameraController = _controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _disposeController();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initialize() async {
    print('🔵 Starting initialization...');
    try {
      // Check if camera is available first
      try {
        _cameras = await availableCameras();
        print('🔵 Cameras found: ${_cameras.length}');
      } catch (e) {
        print('🔴 Error getting cameras: $e');
        setState(() {
          _cameraError = 'Failed to get cameras: $e';
          _isInitialized = true;
          _isLoading = false;
        });
        return;
      }

      // Request camera permission
      final status = await Permission.camera.request();
      print('🔵 Camera permission status: $status');

      if (status != PermissionStatus.granted) {
        setState(() {
          _cameraError =
              'Camera permission denied. Please grant camera permission to use this feature.';
          _isCameraReady = false;
          _isInitialized = true;
          _isLoading = false;
        });
        return;
      }

      // Load settings (don't wait for this to complete)
      _loadSettings()
          .then((_) {
            print('✅ Settings loaded');
          })
          .catchError((e) {
            print('🔴 Error loading settings: $e');
          });

      // Get location (don't wait for this to complete)
      _getLocation()
          .then((_) {
            print('✅ Location loaded');
          })
          .catchError((e) {
            print('🔴 Error getting location: $e');
          });

      // Initialize camera
      await _initializeCamera();

      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });

      print('✅ Initialization complete');
    } catch (e) {
      print('🔴 Initialization error: $e');
      setState(() {
        _cameraError = 'Initialization failed: $e';
        _isInitialized = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _soundOn = prefs.getBool('sound_on_capture') ?? true;
          _vibrateOn = prefs.getBool('vibration_on_capture') ?? true;
          _quality = prefs.getString('image_quality') ?? 'High';
          _watermarkSize = prefs.getDouble('watermark_size') ?? 25.0;
        });
      }

      final title = prefs.getString('app_title');
      if (title?.isNotEmpty == true) MetadataService.setAppTitle(title!);

      final logoPath = prefs.getString('custom_logo_path');
      if (logoPath != null) MetadataService.setCustomLogoPath(logoPath);
    } catch (e) {
      print('🔴 Load settings error: $e');
    }
  }

  Future<void> _getLocation() async {
    try {
      final loc = await MetadataService.getCurrentLocation();
      if (loc != null && mounted) {
        final addr = await MetadataService.getAddressFromCoordinates(
          loc['latitude']!,
          loc['longitude']!,
        );
        if (mounted) {
          setState(() {
            _coordinates = loc;
            _locationAddress = addr ?? "Unknown";
            _isLocationReady = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _locationAddress = "Location unavailable";
            _isLocationReady = true;
          });
        }
      }
    } catch (e) {
      print('🔴 Location error: $e');
      if (mounted) {
        setState(() {
          _locationAddress = "Location error";
          _isLocationReady = true;
        });
      }
    }
  }

  Future<void> _initializeCamera() async {
    print('🔵 Starting camera initialization...');
    try {
      if (_cameras.isEmpty) {
        setState(() {
          _cameraError = 'No cameras found on device';
          _isCameraReady = false;
        });
        return;
      }

      // Print camera info for debugging
      for (var camera in _cameras) {
        print('🔵 Camera available: ${camera.lensDirection}, ${camera.name}');
      }

      // Prefer back camera
      _cameraIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      if (_cameraIndex == -1) _cameraIndex = 0;
      print('🔵 Selected camera index: $_cameraIndex');

      await _disposeController();

      _controller = CameraController(
        _cameras[_cameraIndex],
        _getResolution(),
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      print('🔵 Camera controller created, initializing...');

      try {
        await _controller!.initialize();
        print('✅ Camera initialized successfully');
      } catch (e) {
        print('🔴 Camera initialize error: $e');
        setState(() {
          _cameraError = 'Failed to initialize camera: $e';
          _isCameraReady = false;
        });
        return;
      }

      if (_isDisposed) {
        await _disposeController();
        return;
      }

      await _configureCamera();

      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _cameraError = '';
        });
        print('✅ Camera UI updated - ready: $_isCameraReady');

        // Start grid animation
        _gridAnimation.forward();
      }
    } catch (e) {
      print('🔴 Camera initialization error: $e');
      if (mounted) {
        setState(() {
          _cameraError = 'Camera error: $e';
          _isCameraReady = false;
        });
      }
    }
  }

  Future<void> _configureCamera() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      // Get zoom levels
      try {
        _minZoom = await _controller!.getMinZoomLevel();
        _maxZoom = await _controller!.getMaxZoomLevel();
      } catch (e) {
        print('🔴 Zoom level error: $e');
        _minZoom = 1.0;
        _maxZoom = 10.0;
      }

      _zoomLevel = _minZoom;
      _currentZoom = _minZoom;
      _baseZoom = _minZoom;

      try {
        await _controller!.setZoomLevel(_zoomLevel);
      } catch (e) {
        print('🔴 Set zoom error: $e');
      }

      // Set flash mode
      try {
        await _controller!.setFlashMode(_flashMode);
      } catch (e) {
        print('🔴 Set flash error: $e');
      }

      // Set focus mode
      try {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setExposureMode(ExposureMode.auto);
      } catch (e) {
        print('🔴 Set focus/exposure error: $e');
      }
    } catch (e) {
      print('🔴 Camera config error: $e');
    }
  }

  Future<void> _disposeController() async {
    if (_controller != null) {
      try {
        await _controller!.dispose();
      } catch (e) {
        print('🔴 Dispose error: $e');
      }
      _controller = null;
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
      default:
        return ResolutionPreset.veryHigh;
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing ||
        !_isCameraReady) {
      print('🔴 Cannot take picture - camera not ready');
      return;
    }

    print('🔵 Taking picture...');

    // Trigger shutter animation
    _shutterAnimation.forward().then((_) => _shutterAnimation.reverse());
    _captureAnimation.forward(from: 0.0);

    setState(() => _isCapturing = true);

    // Haptic feedback
    if (_vibrateOn) {
      try {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) Vibration.vibrate(duration: 30);
      } catch (e) {
        print('🔴 Vibration error: $e');
      }
    }

    // Camera shutter sound
    if (_soundOn) {
      SystemSound.play(SystemSoundType.click);
    }

    try {
      final image = await _controller!.takePicture();
      print('✅ Picture taken: ${image.path}');

      final tempDir = await getTemporaryDirectory();
      final tempPath = path.join(
        tempDir.path,
        'capture_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      await File(image.path).rename(tempPath);

      final timestamp = DateTime.now();
      final bytes = await File(tempPath).readAsBytes();

      final processed = await MetadataService.addMetadataToImage(
        bytes,
        timestamp,
        _coordinates,
        _locationAddress,
        locationLabel: '📍',
        addressLabel: '🏠',
        datetimeLabel: '📅',
      );

      final appDir = await getApplicationDocumentsDirectory();
      final capturePath = path.join(
        appDir.path,
        'captured_images',
        'IMG_${timestamp.millisecondsSinceEpoch}.jpg',
      );

      await Directory(path.dirname(capturePath)).create(recursive: true);
      await File(capturePath).writeAsBytes(processed);

      if (await File(tempPath).exists()) {
        await File(tempPath).delete();
      }

      // Add to storage service
      final storage = Provider.of<StorageService>(context, listen: false);
      storage.capturedImages.insert(
        0,
        CapturedImage(
          id: timestamp.millisecondsSinceEpoch.toString(),
          imagePath: capturePath,
          timestamp: timestamp,
          location: _coordinates,
          address: _locationAddress,
        ),
      );

      // Show success animation
      _showCaptureSuccess();
      print('✅ Picture saved: $capturePath');
    } catch (e) {
      print('🔴 Capture failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Capture failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(milliseconds: 800),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  void _showCaptureSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Photo captured!'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _toggleFlash() async {
    if (_controller == null) return;

    const modes = [
      FlashMode.off,
      FlashMode.auto,
      FlashMode.always,
      FlashMode.torch,
    ];
    final currentIndex = modes.indexOf(_flashMode);
    final nextIndex = (currentIndex + 1) % modes.length;
    final newMode = modes[nextIndex];

    try {
      await _controller!.setFlashMode(newMode);
      setState(() => _flashMode = newMode);

      // Haptic feedback
      if (_vibrateOn) {
        try {
          Vibration.vibrate(duration: 10);
        } catch (e) {
          print('🔴 Vibration error: $e');
        }
      }
    } catch (e) {
      print('🔴 Flash mode error: $e');
    }
  }

  void _switchCamera() async {
    if (_cameras.length < 2 || _isCapturing) return;

    print('🔵 Switching camera...');
    setState(() => _isCameraReady = false);

    await _disposeController();

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    print('🔵 New camera index: $_cameraIndex');

    try {
      _controller = CameraController(
        _cameras[_cameraIndex],
        _getResolution(),
        enableAudio: false,
      );

      await _controller!.initialize();
      await _configureCamera();

      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _cameraError = '';
        });
        print('✅ Camera switched successfully');
      }
    } catch (e) {
      print('🔴 Camera switch failed: $e');
      if (mounted) {
        setState(() {
          _cameraError = 'Camera switch failed: $e';
          _isCameraReady = false;
        });
      }
    }
  }

  void _toggleGrid() {
    setState(() => _showGrid = !_showGrid);
    if (_showGrid) {
      _gridAnimation.forward();
    } else {
      _gridAnimation.reverse();
    }

    // Haptic feedback
    if (_vibrateOn) {
      try {
        Vibration.vibrate(duration: 5);
      } catch (e) {
        print('🔴 Vibration error: $e');
      }
    }
  }

  void _onFocusTap(TapUpDetails details) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(details.globalPosition);

    // Ensure position is within bounds
    final size = box.size;
    final x = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final y = (localPosition.dy / size.height).clamp(0.0, 1.0);

    setState(() {
      _showFocusRing = true;
      _focusPosition = localPosition;
    });

    _focusAnimation.forward(from: 0.0);

    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _showFocusRing = false);
      }
    });

    // Set focus and exposure points
    try {
      _controller!.setFocusPoint(Offset(x, y));
      _controller!.setExposurePoint(Offset(x, y));
    } catch (e) {
      print('🔴 Focus error: $e');
    }
  }

  void _onZoomStart(ScaleStartDetails details) {
    _baseZoom = _zoomLevel;
    _zoomIndicatorAnimation.forward();
  }

  void _onZoomUpdate(ScaleUpdateDetails details) {
    if (_maxZoom <= _minZoom) return;

    // Calculate new zoom based on scale gesture
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);

    if ((newZoom - _currentZoom).abs() > 0.05) {
      setState(() {
        _currentZoom = newZoom;
        _zoomLevel = newZoom;
      });

      _zoomDebounceTimer?.cancel();
      _zoomDebounceTimer = Timer(const Duration(milliseconds: 16), () {
        if (_controller != null && _controller!.value.isInitialized) {
          _controller!.setZoomLevel(_zoomLevel);
        }
      });
    }
  }

  void _onZoomEnd(ScaleEndDetails details) {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _zoomIndicatorAnimation.reverse();
      }
    });
  }

  Widget _buildPreview() {
    if (_controller == null || !_controller!.value.isInitialized) {
      print('🔴 Preview not available - building placeholder');
      return Container(
        color: Colors.black,
        child: Center(
          child: Text(
            'Camera preview not available',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    print('✅ Building camera preview');

    // Get screen size
    final size = MediaQuery.of(context).size;

    // Calculate aspect ratio
    final previewSize = _controller!.value.previewSize!;
    final cameraAspectRatio = previewSize.width / previewSize.height;
    final screenAspectRatio = size.width / size.height;

    // Calculate scale to fill screen while maintaining aspect ratio
    double scale = 1.0;
    if (cameraAspectRatio > screenAspectRatio) {
      scale =
          size.width /
          (previewSize.width * screenAspectRatio / cameraAspectRatio);
    } else {
      scale = size.height / previewSize.height;
    }

    return GestureDetector(
      onTapUp: _onFocusTap,
      onScaleStart: _onZoomStart,
      onScaleUpdate: _onZoomUpdate,
      onScaleEnd: _onZoomEnd,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          Center(
            child: Transform.scale(
              scale: scale,
              child: AspectRatio(
                aspectRatio: cameraAspectRatio,
                child: CameraPreview(_controller!),
              ),
            ),
          ),

          // Shutter animation overlay
          AnimatedBuilder(
            animation: _shutterAnimation,
            builder: (_, __) => Container(
              color: Colors.white.withOpacity(_shutterAnimation.value * 0.3),
            ),
          ),

          // Grid overlay
          if (_showGrid)
            AnimatedBuilder(
              animation: _gridAnimation,
              builder: (_, __) => CustomPaint(
                size: Size(size.width, size.height),
                painter: GridPainter(
                  opacity: _gridAnimation.value,
                  color: Colors.white,
                ),
              ),
            ),

          // Focus ring
          if (_showFocusRing)
            AnimatedBuilder(
              animation: _focusAnimation,
              builder: (_, __) => Positioned(
                left: _focusPosition.dx - 40,
                top: _focusPosition.dy - 40,
                child: Opacity(
                  opacity: 1 - _focusAnimation.value,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _primaryOrange,
                        width: 2 + _focusAnimation.value * 2,
                      ),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Center(
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _primaryOrange,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print(
      '🔵 Building UI - isLoading: $_isLoading, isInitialized: $_isInitialized, isCameraReady: $_isCameraReady, error: $_cameraError',
    );

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (!_isInitialized) {
      return _buildLoadingState();
    }

    if (_cameraError.isNotEmpty) {
      return _buildErrorState();
    }

    if (!_isCameraReady) {
      return _buildLoadingState();
    }

    return _buildCameraInterface();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 80),
            SizedBox(height: 24),
            Text(
              'Camera Error',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Text(
              _cameraError,
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: _initialize,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: Text(
                'Retry',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
            SizedBox(height: 16),
            TextButton(
              onPressed: () {
                openAppSettings();
              },
              child: Text(
                'Open App Settings',
                style: TextStyle(color: _primaryOrange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraInterface() {
    return Stack(
      children: [
        // Camera preview
        _buildPreview(),

        // Gradient overlays for better UI readability
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.5),
                Colors.transparent,
                Colors.transparent,
                Colors.black.withOpacity(0.5),
              ],
              stops: const [0.0, 0.2, 0.8, 1.0],
            ),
          ),
        ),

        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildIconButton(icon: _getFlashIcon(), onTap: _toggleFlash),
                Row(
                  children: [
                    _buildIconButton(
                      icon: Icons.grid_on,
                      onTap: _toggleGrid,
                      isActive: _showGrid,
                    ),
                    const SizedBox(width: 10),
                    _buildIconButton(
                      icon: Icons.cameraswitch,
                      onTap: _switchCamera,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Zoom indicator
        AnimatedBuilder(
          animation: _zoomIndicatorAnimation,
          builder: (_, __) => Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Opacity(
                opacity: _zoomIndicatorAnimation.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.zoom_in, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${_zoomLevel.toStringAsFixed(1)}x',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Location info
        if (_locationAddress.isNotEmpty && _locationAddress != "Unknown")
          Positioned(
            top: 140,
            left: 20,
            right: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Color(0xFFFFCC70),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _locationAddress,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Bottom controls
        Positioned(
          bottom: 30,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildGalleryThumb(),
              _buildCaptureButton(),
              _buildSettingsButton(),
            ],
          ),
        ),

        // Capture animation
        AnimatedBuilder(
          animation: _captureAnimation,
          builder: (_, __) => Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.white.withOpacity(_captureAnimation.value * 0.3),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? _primaryBlue.withOpacity(0.9)
              : Colors.black.withOpacity(0.4),
          border: Border.all(
            color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.white : Colors.white.withOpacity(0.9),
          size: 22,
        ),
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _isCapturing ? null : _takePicture,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: _isCapturing ? 2 : 4),
        ),
        child: Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_primaryBlue, _primaryPurple, _primaryOrange],
              ),
            ),
            child: _isCapturing
                ? const Center(
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildGalleryThumb() {
    final storage = Provider.of<StorageService>(context);

    return GestureDetector(
      onTap: () {
        // Navigate to gallery
        // You can implement navigation here
      },
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _primaryBlue.withOpacity(0.3),
              _primaryPurple.withOpacity(0.3),
            ],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: storage.capturedImages.isNotEmpty
              ? Image.file(
                  File(storage.capturedImages.first.imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.photo, color: Colors.white),
                )
              : const Icon(Icons.photo_library, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildSettingsButton() {
    return _buildIconButton(
      icon: Icons.tune,
      onTap: () {
        // Navigate to settings
      },
    );
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.flashlight_on;
      default:
        return Icons.flash_off;
    }
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder(
            duration: const Duration(seconds: 2),
            tween: Tween<double>(begin: 0, end: 2 * pi),
            builder: (_, double angle, __) {
              return Transform.rotate(
                angle: angle,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        _primaryBlue,
                        _primaryPurple,
                        _primaryOrange,
                        _primaryBlue,
                      ],
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            _cameraError.isNotEmpty ? _cameraError : 'Initializing camera...',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    print('🔵 Disposing CoolCameraScreen');
    WidgetsBinding.instance.removeObserver(this);
    _isDisposed = true;
    _shutterAnimation.dispose();
    _focusAnimation.dispose();
    _zoomIndicatorAnimation.dispose();
    _gridAnimation.dispose();
    _captureAnimation.dispose();
    _focusTimer?.cancel();
    _zoomDebounceTimer?.cancel();
    _disposeController();
    super.dispose();
  }
}

// Custom painter for grid overlay
class GridPainter extends CustomPainter {
  final double opacity;
  final Color color;

  GridPainter({required this.opacity, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;

    final paint = Paint()
      ..color = color.withOpacity(opacity * 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final double thirdWidth = size.width / 3;
    final double thirdHeight = size.height / 3;

    // Draw vertical lines
    canvas.drawLine(
      Offset(thirdWidth, 0),
      Offset(thirdWidth, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(thirdWidth * 2, 0),
      Offset(thirdWidth * 2, size.height),
      paint,
    );

    // Draw horizontal lines
    canvas.drawLine(
      Offset(0, thirdHeight),
      Offset(size.width, thirdHeight),
      paint,
    );
    canvas.drawLine(
      Offset(0, thirdHeight * 2),
      Offset(size.width, thirdHeight * 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.opacity != opacity || oldDelegate.color != color;
  }
}
