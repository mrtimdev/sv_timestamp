// // lib/screens/camera_screen.dart

// import 'dart:async';
// import 'dart:math';
// import 'dart:io';
// import 'dart:ui';

// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:native_device_orientation/native_device_orientation.dart';
// import 'package:provider/provider.dart';
// import 'package:camera/camera.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:path/path.dart' as path;
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:sv_timestamp/l10n/app_localizations.dart';
// import 'package:sv_timestamp/screens/SettingsScreen.dart';
// import 'package:sv_timestamp/screens/gallery_screen.dart';
// import 'package:vibration/vibration.dart';
// import 'package:sv_timestamp/models/captured_image.dart';
// import '../utils/metadata_service.dart';
// import '../utils/storage_service.dart';

// class CameraScreen extends StatefulWidget {
//   const CameraScreen({super.key});

//   @override
//   State<CameraScreen> createState() => _CameraScreenState();
// }

// class _CameraScreenState extends State<CameraScreen>
//     with WidgetsBindingObserver, TickerProviderStateMixin {
//   // Core
//   late StorageService _storageService;
//   CameraController? _controller;
//   List<CameraDescription> _cameras = [];
//   bool _isControllerInitialized = false;
//   bool _isInitializing = false;

//   // State
//   bool _isCameraReady = false;
//   bool _isCapturing = false;
//   bool _isLocationReady = false;
//   String _cameraError = '';

//   // Camera settings
//   int _cameraIndex = 0;
//   FlashMode _flashMode = FlashMode.auto;
//   double _zoom = 1.0;
//   double _minZoom = 1.0;
//   double _maxZoom = 10.0;
//   bool _isZooming = false;
//   double _baseZoom = 1.0;

//   // Focus ring
//   bool _showFocusRing = false;
//   Offset _focusPosition = Offset.zero;
//   late AnimationController _focusAnimation;
//   Timer? _focusTimer;

//   // Location
//   Map<String, double>? _coords;
//   String _address = "Loading...";

//   // User settings
//   late SharedPreferences _prefs;
//   bool _soundOn = true;
//   bool _vibrateOn = true;
//   String _quality = 'High';
//   double _watermarkSize = 25.0;
//   bool _keepOriginal = true;

//   // Animation
//   late AnimationController _captureAnim;

//   // Zoom debounce
//   Timer? _zoomDebounceTimer;

//   // Rotation handling
//   bool _isDisposed = false;
//   bool _isNavigatingAway = false;

//   // Orientation
//   Orientation _currentOrientation = Orientation.portrait;

//   // Add a flag to track if camera is initializing
//   bool _isCameraInitializing = false;

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);

//     _captureAnim = AnimationController(
//       duration: const Duration(milliseconds: 200),
//       vsync: this,
//     );

//     _focusAnimation = AnimationController(
//       duration: const Duration(milliseconds: 300),
//       vsync: this,
//     );

//     _init();
//   }

//   Future<void> _init() async {
//     if (_isInitializing) return;
//     _isInitializing = true;

//     try {
//       await _loadPrefs();
//       await _initLocation();
//       await _initCamera();
//     } catch (e) {
//       print('Init error: $e');
//     } finally {
//       _isInitializing = false;
//     }
//   }

//   Future<void> _loadPrefs() async {
//     _prefs = await SharedPreferences.getInstance();
//     if (_isDisposed) return;

//     setState(() {
//       _soundOn = _prefs.getBool('sound_on_capture') ?? true;
//       _vibrateOn = _prefs.getBool('vibration_on_capture') ?? true;
//       _quality = _prefs.getString('image_quality') ?? 'High';
//       _watermarkSize = _prefs.getDouble('watermark_size') ?? 25.0;
//       _keepOriginal = _prefs.getBool('keep_original') ?? true;

//       final title = _prefs.getString('app_title');
//       if (title?.isNotEmpty == true) MetadataService.setAppTitle(title!);

//       final logoPath = _prefs.getString('custom_logo_path');
//       if (logoPath != null) MetadataService.setCustomLogoPath(logoPath);
//     });
//   }

//   Future<void> _initLocation() async {
//     try {
//       final loc = await MetadataService.getCurrentLocation();
//       if (_isDisposed) return;

//       if (loc != null && mounted) {
//         final addr = await MetadataService.getAddressFromCoordinates(
//           loc['latitude']!,
//           loc['longitude']!,
//         );
//         setState(() {
//           _coords = loc;
//           _address = addr ?? "Unknown";
//           _isLocationReady = true;
//         });
//       } else {
//         if (mounted) {
//           setState(() {
//             _address = "Location unavailable";
//             _isLocationReady = true;
//           });
//         }
//       }
//     } catch (e) {
//       if (mounted) {
//         setState(() {
//           _address = "Location error";
//           _isLocationReady = true;
//         });
//       }
//     }
//   }

//   Future<void> _initCamera() async {
//     if (_isDisposed || _isNavigatingAway || _isCameraInitializing) return;

//     _isCameraInitializing = true;

//     try {
//       _cameras = await availableCameras();

//       if (_cameras.isEmpty) {
//         if (mounted) {
//           setState(() {
//             _cameraError = 'No cameras found';
//             _isCameraReady = false;
//           });
//         }
//         return;
//       }

//       _cameraIndex = _cameras.indexWhere(
//         (camera) => camera.lensDirection == CameraLensDirection.back,
//       );
//       if (_cameraIndex == -1) _cameraIndex = 0;

//       await _disposeController();

//       // Reset zoom before creating controller
//       _zoom = 1.0;
//       _baseZoom = 1.0;

//       _controller = CameraController(
//         _cameras[_cameraIndex],
//         _getResolution(),
//         enableAudio: false,
//         imageFormatGroup: ImageFormatGroup.jpeg,
//       );

//       // Add listener before initialization
//       _controller!.addListener(_onCameraControllerListener);

//       await _controller!.initialize();

//       if (_isDisposed || _isNavigatingAway) {
//         await _disposeController();
//         return;
//       }

//       _isControllerInitialized = true;

//       await _configureCamera();

//       if (mounted && !_isDisposed && !_isNavigatingAway) {
//         setState(() {
//           _isCameraReady = true;
//           _cameraError = '';
//         });
//       }
//     } on CameraException catch (e) {
//       print('CameraException: ${e.code} - ${e.description}');
//       _handleCameraError('Camera error: ${e.description}');
//     } catch (e) {
//       print('Camera init error: $e');
//       _handleCameraError('Camera initialization failed: $e');
//     } finally {
//       _isCameraInitializing = false;
//     }
//   }

//   void _onCameraControllerListener() {
//     if (_isDisposed || _isNavigatingAway || !mounted || _controller == null)
//       return;

//     if (_controller!.value.hasError) {
//       _handleCameraError(
//         'Camera error: ${_controller!.value.errorDescription}',
//       );
//     }
//   }

//   void _handleCameraError(String error) {
//     if (mounted && !_isDisposed && !_isNavigatingAway) {
//       setState(() {
//         _cameraError = error;
//         _isCameraReady = false;
//       });
//     }
//   }

//   Future<void> _configureCamera() async {
//     if (_controller == null || !_controller!.value.isInitialized) return;

//     try {
//       try {
//         _minZoom = await _controller!.getMinZoomLevel();
//         _maxZoom = await _controller!.getMaxZoomLevel();
//         // Ensure zoom is within bounds and set explicitly
//         _zoom = _zoom.clamp(_minZoom, _maxZoom);
//         await _controller!.setZoomLevel(_zoom);
//       } catch (e) {
//         print('Zoom not supported: $e');
//         _minZoom = 1.0;
//         _maxZoom = 1.0;
//         _zoom = 1.0;
//       }

//       await _controller!.setFocusMode(FocusMode.auto);
//       await _controller!.setExposureMode(ExposureMode.auto);
//       await _controller!.setFlashMode(_flashMode);
//     } catch (e) {
//       print('Camera configuration error: $e');
//     }
//   }

//   Future<void> _disposeController() async {
//     if (_controller != null) {
//       // Remove listener first
//       try {
//         _controller!.removeListener(_onCameraControllerListener);
//       } catch (e) {
//         print('Error removing listener: $e');
//       }

//       try {
//         await _controller!.dispose();
//       } catch (e) {
//         print('Error disposing controller: $e');
//       }
//       _controller = null;
//       _isControllerInitialized = false;
//       _isCameraReady = false;
//     }
//   }

//   ResolutionPreset _getResolution() {
//     switch (_quality) {
//       case 'Low':
//         return ResolutionPreset.medium;
//       case 'Medium':
//         return ResolutionPreset.high;
//       case 'Ultra':
//         return ResolutionPreset.max;
//       case 'High':
//       default:
//         return ResolutionPreset.veryHigh;
//     }
//   }

//   bool _canTakePicture() {
//     return _controller != null &&
//         _controller!.value.isInitialized &&
//         !_isCapturing &&
//         _isControllerInitialized &&
//         _isCameraReady &&
//         !_isDisposed &&
//         !_isNavigatingAway;
//   }

//   Future<void> _takePicture() async {
//     if (!_canTakePicture()) return;

//     try {
//       await _controller!.setFocusMode(FocusMode.auto);
//       await _controller!.setExposureMode(ExposureMode.auto);
//     } catch (e) {
//       print('Focus/Exposure error: $e');
//     }

//     _captureAnim.forward();
//     setState(() => _isCapturing = true);

//     if (_soundOn) {
//       SystemSound.play(SystemSoundType.click);
//     }

//     if (_vibrateOn) {
//       try {
//         final hasVibrator = await Vibration.hasVibrator();
//         if (hasVibrator == true) {
//           Vibration.vibrate(duration: 50);
//         }
//       } catch (e) {
//         print('Vibration error: $e');
//       }
//     }

//     try {
//       final image = await _controller!.takePicture();

//       final tempDir = await getTemporaryDirectory();
//       final tempPath = path.join(
//         tempDir.path,
//         'temp_${DateTime.now().millisecondsSinceEpoch}.jpg',
//       );

//       await File(image.path).rename(tempPath);

//       final timestamp = DateTime.now();
//       final loc = AppLocalizations.of(context)!;

//       final originalBytes = await File(tempPath).readAsBytes();

//       final appDir = await getApplicationDocumentsDirectory();
//       final captureDir = path.join(appDir.path, 'captured_images');
//       final fileName = 'IMG_${timestamp.millisecondsSinceEpoch}';

//       String? originalPath;
//       if (_keepOriginal) {
//         originalPath = path.join(captureDir, 'original', '$fileName.jpg');
//         await Directory(path.dirname(originalPath)).create(recursive: true);
//         await File(originalPath).writeAsBytes(originalBytes);
//       }

//       final processed = await MetadataService.addMetadataToImage(
//         originalBytes,
//         timestamp,
//         _coords,
//         _address,
//         locationLabel: loc.locationLabel,
//         addressLabel: loc.addressLabel,
//         datetimeLabel: loc.datetimeLabel,
//       );

//       final watermarkedPath = path.join(
//         captureDir,
//         'watermarked',
//         '$fileName.jpg',
//       );
//       await Directory(path.dirname(watermarkedPath)).create(recursive: true);
//       await File(watermarkedPath).writeAsBytes(processed);

//       if (await File(tempPath).exists()) {
//         await File(tempPath).delete();
//       }

//       _storageService.capturedImages.insert(
//         0,
//         CapturedImage(
//           id: timestamp.millisecondsSinceEpoch.toString(),
//           imagePath: watermarkedPath,
//           originalPath: originalPath,
//           timestamp: timestamp,
//           location: _coords,
//           address: _address,
//           additionalData: {
//             'quality': _quality,
//             'zoom': _zoom.toStringAsFixed(1),
//             'flash': _flashMode.toString(),
//           },
//         ),
//       );

//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('✓ Captured...'),
//             backgroundColor: Colors.green,
//             duration: Duration(milliseconds: 800),
//           ),
//         );
//       }
//     } catch (e) {
//       print('Capture error: $e');
//       if (mounted) {
//         final errorMsg = e.toString();
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text(
//               'Failed: ${errorMsg.substring(0, min(50, errorMsg.length))}',
//             ),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     } finally {
//       if (mounted) {
//         _captureAnim.reverse();
//         setState(() => _isCapturing = false);
//       }
//     }
//   }

//   Future<void> _switchCamera() async {
//     if (_cameras.length < 2 || _isCapturing || _isCameraInitializing) return;

//     _zoomDebounceTimer?.cancel();
//     _isCameraInitializing = true;

//     // Update UI to show loading state
//     setState(() {
//       _isCameraReady = false;
//       _isControllerInitialized = false;
//       _isZooming = false;
//       _zoom = 1.0;
//       _baseZoom = 1.0;
//     });

//     try {
//       await _disposeController();

//       _cameraIndex = (_cameraIndex + 1) % _cameras.length;

//       _controller = CameraController(
//         _cameras[_cameraIndex],
//         _getResolution(),
//         enableAudio: false,
//         imageFormatGroup: ImageFormatGroup.jpeg,
//       );

//       // Add listener before initialization
//       _controller!.addListener(_onCameraControllerListener);

//       await _controller!.initialize();

//       if (_isDisposed || _isNavigatingAway) {
//         await _disposeController();
//         return;
//       }

//       _isControllerInitialized = true;

//       // Configure camera settings
//       try {
//         _minZoom = await _controller!.getMinZoomLevel();
//         _maxZoom = await _controller!.getMaxZoomLevel();
//         _zoom = _minZoom > 1.0 ? _minZoom : 1.0;
//         _baseZoom = _zoom;
//         await _controller!.setZoomLevel(_zoom);
//       } catch (e) {
//         print('Zoom not supported on this camera: $e');
//         _minZoom = 1.0;
//         _maxZoom = 1.0;
//         _zoom = 1.0;
//         _baseZoom = 1.0;
//       }

//       await _controller!.setFocusMode(FocusMode.auto);
//       await _controller!.setExposureMode(ExposureMode.auto);
//       await _controller!.setFlashMode(_flashMode);

//       if (mounted && !_isDisposed && !_isNavigatingAway) {
//         setState(() {
//           _isCameraReady = true;
//           _cameraError = '';
//         });
//       }
//     } catch (e) {
//       print('Switch camera error: $e');
//       if (mounted && !_isDisposed && !_isNavigatingAway) {
//         setState(() {
//           _cameraError = 'Failed to switch camera: $e';
//           _isCameraReady = false;
//         });
//       }
//     } finally {
//       _isCameraInitializing = false;
//     }
//   }

//   void _toggleFlash() async {
//     if (!_canInteractWithCamera()) return;

//     try {
//       const modes = [
//         FlashMode.off,
//         FlashMode.auto,
//         FlashMode.always,
//         FlashMode.torch,
//       ];
//       final currentIndex = modes.indexOf(_flashMode);
//       final nextIndex = (currentIndex + 1) % modes.length;
//       final newMode = modes[nextIndex];

//       await _controller!.setFlashMode(newMode);
//       if (mounted) setState(() => _flashMode = newMode);
//     } catch (e) {
//       print('Flash error: $e');
//     }
//   }

//   bool _canInteractWithCamera() {
//     return _controller != null &&
//         _controller!.value.isInitialized &&
//         _isCameraReady &&
//         !_isCapturing &&
//         !_isDisposed &&
//         !_isNavigatingAway;
//   }

//   void _onScaleStart(ScaleStartDetails details) {
//     if (!_canInteractWithCamera()) return;
//     _baseZoom = _zoom;
//     setState(() => _isZooming = true);
//   }

//   void _onScaleUpdate(ScaleUpdateDetails details) async {
//     if (!_canInteractWithCamera() || _controller == null) return;

//     try {
//       double zoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
//       if ((zoom - _zoom).abs() > 0.01) {
//         await _controller!.setZoomLevel(zoom);
//         if (mounted && !_isDisposed) {
//           setState(() => _zoom = zoom);
//         }
//       }
//     } catch (e) {
//       print('Zoom error: $e');
//     }
//   }

//   void _onScaleEnd(ScaleEndDetails details) {
//     if (mounted) setState(() => _isZooming = false);
//   }

//   void _onFocusTap(TapUpDetails details) {
//     if (!_canInteractWithCamera() || _controller == null) return;

//     final box = context.findRenderObject() as RenderBox;
//     final localPosition = box.globalToLocal(details.globalPosition);
//     final size = box.size;

//     double x = (localPosition.dx / size.width).clamp(0.0, 1.0);
//     double y = (localPosition.dy / size.height).clamp(0.0, 1.0);

//     setState(() {
//       _showFocusRing = true;
//       _focusPosition = localPosition;
//     });

//     _focusAnimation.forward(from: 0.0);

//     _focusTimer?.cancel();
//     _focusTimer = Timer(const Duration(milliseconds: 2000), () {
//       if (mounted) setState(() => _showFocusRing = false);
//     });

//     try {
//       _controller!.setFocusPoint(Offset(x, y));
//       _controller!.setExposurePoint(Offset(x, y));
//     } catch (e) {
//       print('Focus error: $e');
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     _storageService = Provider.of<StorageService>(context);

//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: OrientationBuilder(
//         builder: (context, orientation) {
//           _currentOrientation = orientation;
//           return _buildBody();
//         },
//       ),
//     );
//   }

//   Widget _buildBody() {
//     if (_cameraError.isNotEmpty && !_isCameraReady) {
//       return _buildError();
//     }

//     return _buildCamera();
//   }

//   Widget _buildCamera() {
//     return Stack(
//       fit: StackFit.expand,
//       children: [
//         _buildPreview(),

//         if (_showFocusRing)
//           Positioned(
//             left: _focusPosition.dx - 40,
//             top: _focusPosition.dy - 40,
//             child: AnimatedBuilder(
//               animation: _focusAnimation,
//               builder: (_, __) => Opacity(
//                 opacity: 1 - _focusAnimation.value,
//                 child: Container(
//                   width: 80,
//                   height: 80,
//                   decoration: BoxDecoration(
//                     border: Border.all(color: Colors.amber, width: 2),
//                     borderRadius: BorderRadius.circular(40),
//                   ),
//                   child: Center(
//                     child: Container(
//                       width: 6,
//                       height: 6,
//                       decoration: const BoxDecoration(
//                         color: Colors.amber,
//                         shape: BoxShape.circle,
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ),

//         SafeArea(
//           child: _currentOrientation == Orientation.portrait
//               ? _buildPortraitUI()
//               : _buildLandscapeUI(),
//         ),
//       ],
//     );
//   }

//   Widget _buildPreview() {
//     // Safe check for controller and initialization
//     if (_controller == null ||
//         !_controller!.value.isInitialized ||
//         !_isCameraReady ||
//         _isCameraInitializing) {
//       return _buildLoading();
//     }

//     // Full-screen camera preview with proper scaling
//     return GestureDetector(
//       onTapUp: _onFocusTap,
//       onScaleStart: _onScaleStart,
//       onScaleUpdate: _onScaleUpdate,
//       onScaleEnd: _onScaleEnd,
//       behavior: HitTestBehavior.opaque,
//       child: Container(
//         width: double.infinity,
//         height: double.infinity,
//         color: Colors.black,
//         child: CameraPreview(_controller!),
//       ),
//     );
//   }

//   Widget _buildLoading() {
//     return Container(
//       color: Colors.black,
//       child: Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             const CircularProgressIndicator(color: Colors.white),
//             const SizedBox(height: 20),
//             Text(
//               _isCameraInitializing
//                   ? 'Switching camera...'
//                   : 'Initializing camera...',
//               style: const TextStyle(color: Colors.white),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // Modern iOS-style frosted glass top bar
//   Widget _buildTopBar() {
//     return ClipRRect(
//       borderRadius: BorderRadius.circular(20),
//       child: BackdropFilter(
//         filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
//         child: Container(
//           padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//           decoration: BoxDecoration(
//             color: Colors.white.withOpacity(0.15),
//             borderRadius: BorderRadius.circular(20),
//             border: Border.all(
//               color: Colors.white.withOpacity(0.2),
//               width: 0.5,
//             ),
//           ),
//           child: Row(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               _flashButton(),
//               const SizedBox(width: 16),
//               _iconButton(
//                 Icons.cameraswitch_outlined,
//                 _switchCamera,
//                 enabled:
//                     _cameras.length > 1 &&
//                     !_isCapturing &&
//                     !_isCameraInitializing,
//               ),
//               const SizedBox(width: 16),
//               _iconButton(
//                 Icons.settings_outlined,
//                 _navigateToSettings,
//                 enabled: !_isCapturing && !_isCameraInitializing,
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   // Flash button with "Auto" label when in auto mode
//   Widget _flashButton() {
//     final isAuto = _flashMode == FlashMode.auto;
//     final canInteract = _canInteractWithCamera();

//     return GestureDetector(
//       onTap: canInteract ? _toggleFlash : null,
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//         decoration: isAuto
//             ? BoxDecoration(
//                 color: Colors.white.withOpacity(0.3),
//                 borderRadius: BorderRadius.circular(12),
//               )
//             : null,
//         child: Row(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(
//               _flashIcon,
//               color: canInteract ? Colors.white : Colors.white30,
//               size: 22,
//             ),
//             if (isAuto) ...[
//               const SizedBox(width: 4),
//               Text(
//                 'Auto',
//                 style: TextStyle(
//                   color: canInteract ? Colors.white : Colors.white30,
//                   fontSize: 13,
//                   fontWeight: FontWeight.w500,
//                 ),
//               ),
//             ],
//           ],
//         ),
//       ),
//     );
//   }

//   // Modern iOS-style frosted glass bottom panel
//   Widget _buildBottomPanel() {
//     return ClipRRect(
//       borderRadius: const BorderRadius.only(
//         topLeft: Radius.circular(24),
//         topRight: Radius.circular(24),
//       ),
//       child: BackdropFilter(
//         filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
//         child: Container(
//           padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
//           decoration: BoxDecoration(
//             color: Colors.white.withOpacity(0.15),
//             borderRadius: const BorderRadius.only(
//               topLeft: Radius.circular(24),
//               topRight: Radius.circular(24),
//             ),
//             border: Border(
//               top: BorderSide(color: Colors.white.withOpacity(0.2), width: 0.5),
//             ),
//           ),
//           child: SafeArea(
//             top: false,
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               children: [
//                 _galleryThumb(),
//                 _captureButton(),
//                 _iconButton(
//                   Icons.brush_outlined,
//                   _showWatermarkSettings,
//                   enabled: !_isCapturing && !_isCameraInitializing,
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildPortraitUI() {
//     return Column(
//       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//       children: [
//         // Top bar with frosted glass effect
//         Padding(
//           padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
//           child: Align(alignment: Alignment.topCenter, child: _buildTopBar()),
//         ),

//         if (_isZooming) Center(child: _buildZoomIndicator()),

//         // Bottom frosted panel
//         _buildBottomPanel(),
//       ],
//     );
//   }

//   Widget _buildLandscapeUI() {
//     return NativeDeviceOrientedWidget(
//       useSensor: true,
//       portraitUp: (context) => _buildOrientedUI(0),
//       portraitDown: (context) => _buildOrientedUI(2),
//       landscapeLeft: (context) => _buildOrientedUI(3),
//       landscapeRight: (context) => _buildOrientedUI(1),
//       fallback: (context) => _buildOrientedUI(0),
//     );
//   }

//   Widget _buildOrientedUI(int quarterTurns) {
//     return AnnotatedRegion<SystemUiOverlayStyle>(
//       value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
//       child: RotatedBox(
//         quarterTurns: quarterTurns,
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             Padding(
//               padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
//               child: Align(
//                 alignment: Alignment.topCenter,
//                 child: _buildTopBar(),
//               ),
//             ),

//             if (_isZooming) Center(child: _buildZoomIndicator()),

//             _buildBottomPanel(),
//           ],
//         ),
//       ),
//     );
//   }

//   IconData get _flashIcon {
//     switch (_flashMode) {
//       case FlashMode.off:
//         return Icons.flash_off_rounded;
//       case FlashMode.auto:
//         return Icons.flash_on_rounded;
//       case FlashMode.torch:
//         return Icons.flashlight_on_rounded;
//       default:
//         return Icons.flash_on_rounded;
//     }
//   }

//   Widget _buildZoomIndicator() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//       decoration: BoxDecoration(
//         color: Colors.black.withOpacity(0.7),
//         borderRadius: BorderRadius.circular(20),
//       ),
//       child: Text(
//         '${_zoom.toStringAsFixed(1)}x',
//         style: const TextStyle(color: Colors.white, fontSize: 14),
//       ),
//     );
//   }

//   Widget _galleryThumb() {
//     final hasImages = _storageService.capturedImages.isNotEmpty;

//     return GestureDetector(
//       onTap: hasImages ? _showGallery : null,
//       child: Container(
//         width: 48,
//         height: 48,
//         decoration: BoxDecoration(
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(
//             color: hasImages ? Colors.white.withOpacity(0.5) : Colors.white30,
//             width: 2,
//           ),
//           color: Colors.black.withOpacity(0.3),
//         ),
//         child: ClipRRect(
//           borderRadius: BorderRadius.circular(10),
//           child: hasImages
//               ? Image.file(
//                   File(_storageService.capturedImages.first.imagePath),
//                   fit: BoxFit.cover,
//                   errorBuilder: (_, __, ___) => Icon(
//                     Icons.photo_library,
//                     color: hasImages ? Colors.white : Colors.white30,
//                     size: 24,
//                   ),
//                 )
//               : Icon(Icons.photo_library, color: Colors.white30, size: 24),
//         ),
//       ),
//     );
//   }

//   // Modern iOS-style capture button with white ring and solid center
//   Widget _captureButton() {
//     final canCapture = _canTakePicture();

//     return AnimatedBuilder(
//       animation: _captureAnim,
//       builder: (_, __) => Transform.scale(
//         scale: 1 - (_captureAnim.value * 0.1),
//         child: GestureDetector(
//           onTap: canCapture ? _takePicture : null,
//           child: Container(
//             width: 72,
//             height: 72,
//             decoration: BoxDecoration(
//               shape: BoxShape.circle,
//               border: Border.all(
//                 color: canCapture ? Colors.white : Colors.white30,
//                 width: 4,
//               ),
//             ),
//             child: Center(
//               child: _isCapturing
//                   ? SizedBox(
//                       width: 56,
//                       height: 56,
//                       child: CircularProgressIndicator(
//                         valueColor: const AlwaysStoppedAnimation<Color>(
//                           Colors.white,
//                         ),
//                         strokeWidth: 3,
//                         backgroundColor: Colors.transparent,
//                       ),
//                     )
//                   : Container(
//                       width: 56,
//                       height: 56,
//                       decoration: BoxDecoration(
//                         shape: BoxShape.circle,
//                         color: canCapture ? Colors.white : Colors.white30,
//                       ),
//                     ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _iconButton(IconData icon, VoidCallback onTap, {bool enabled = true}) {
//     return IconButton(
//       icon: Icon(
//         icon,
//         color: enabled ? Colors.white : Colors.white30,
//         size: 26,
//       ),
//       onPressed: enabled ? onTap : null,
//       padding: EdgeInsets.zero,
//       constraints: const BoxConstraints(),
//     );
//   }

//   Widget _buildError() {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           const Icon(Icons.error_outline, color: Colors.red, size: 48),
//           const SizedBox(height: 16),
//           Text(
//             _cameraError,
//             style: const TextStyle(color: Colors.white),
//             textAlign: TextAlign.center,
//           ),
//           const SizedBox(height: 20),
//           ElevatedButton(onPressed: _initCamera, child: const Text('Retry')),
//         ],
//       ),
//     );
//   }

//   void _navigateToSettings() async {
//     if (_isNavigatingAway || _isCapturing) return;

//     _isNavigatingAway = true;

//     // Dispose first, then navigate
//     await _disposeController();
//     if (!mounted) return;

//     await Navigator.push(
//       context,
//       MaterialPageRoute(builder: (_) => const SettingsScreen()),
//     );

//     if (mounted) {
//       _isNavigatingAway = false;
//       await _loadPrefs();
//       await _initCamera();
//     }
//   }

//   void _showWatermarkSettings() {
//     if (!mounted || _isCapturing) return;

//     double tempSize = _watermarkSize;

//     showModalBottomSheet(
//       context: context,
//       backgroundColor: const Color(0xFF1E1E1E),
//       isDismissible: true,
//       enableDrag: true,
//       builder: (context) => StatefulBuilder(
//         builder: (context, setModalState) => Padding(
//           padding: const EdgeInsets.all(20),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               const Text(
//                 'Watermark Size',
//                 style: TextStyle(
//                   color: Colors.white,
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const SizedBox(height: 20),
//               Row(
//                 children: [
//                   const Icon(Icons.text_fields, color: Colors.white),
//                   Expanded(
//                     child: Slider(
//                       value: tempSize,
//                       min: 20,
//                       max: 100,
//                       divisions: 16,
//                       activeColor: Colors.blue,
//                       onChanged: (v) => setModalState(() => tempSize = v),
//                     ),
//                   ),
//                   Text(
//                     '${tempSize.toInt()}px',
//                     style: const TextStyle(color: Colors.white),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 20),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                 children: [
//                   TextButton(
//                     onPressed: () => Navigator.pop(context),
//                     child: const Text('Cancel'),
//                   ),
//                   ElevatedButton(
//                     onPressed: () {
//                       setState(() => _watermarkSize = tempSize);
//                       _prefs.setDouble('watermark_size', tempSize);
//                       Navigator.pop(context);
//                     },
//                     child: const Text('Apply'),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   void _showGallery() async {
//     if (_storageService.capturedImages.isEmpty) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(const SnackBar(content: Text('No photos yet')));
//       return;
//     }

//     if (_isNavigatingAway) return;

//     _isNavigatingAway = true;
//     await _disposeController();

//     if (!mounted) return;

//     GalleryScreenBottomSheet.show(context);

//     if (mounted) {
//       _isNavigatingAway = false;
//       await _initCamera();
//     }
//   }

//   @override
//   void dispose() {
//     _isDisposed = true;
//     WidgetsBinding.instance.removeObserver(this);
//     _captureAnim.dispose();
//     _focusAnimation.dispose();
//     _zoomDebounceTimer?.cancel();
//     _focusTimer?.cancel();
//     _disposeController();
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (_isDisposed || _isNavigatingAway) return;

//     switch (state) {
//       case AppLifecycleState.resumed:
//         if (_controller == null || !_controller!.value.isInitialized) {
//           _initCamera();
//         }
//         break;
//       case AppLifecycleState.paused:
//       case AppLifecycleState.inactive:
//       case AppLifecycleState.detached:
//       case AppLifecycleState.hidden:
//         if (!_isNavigatingAway) {
//           _disposeController();
//         }
//         break;
//     }
//   }
// }
