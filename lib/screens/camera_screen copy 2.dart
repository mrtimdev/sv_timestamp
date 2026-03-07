import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isRearCamera = true;
  bool _isRecording = false;
  bool _isFlashOn = false;
  double _currentZoomLevel = 1.0;
  double _maxZoomLevel = 4.0;
  ResolutionPreset _currentResolution = ResolutionPreset.medium;
  File? _capturedImage;
  late AnimationController _flashAnimationController;
  Timer? _recordingTimer;
  int _recordingDuration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flashAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _flashAnimationController.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        await _initCameraController(_cameras![_isRearCamera ? 0 : 1]);
      }
    } catch (e) {
      _showErrorSnackBar('Error initializing camera: $e');
    }
  }

  Future<void> _initCameraController(CameraDescription camera) async {
    _controller = CameraController(
      camera,
      _currentResolution,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();
      _maxZoomLevel = await _controller!.getMaxZoomLevel() ?? 4.0;

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      _showErrorSnackBar('Error initializing camera controller: $e');
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;

    setState(() {
      _isRearCamera = !_isRearCamera;
      _isInitialized = false;
    });

    await _initCameraController(_cameras![_isRearCamera ? 0 : 1]);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _isFlashOn = !_isFlashOn;
    });

    await _controller!.setFlashMode(
      _isFlashOn ? FlashMode.torch : FlashMode.off,
    );
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      // Flash animation
      _flashAnimationController.forward().then((_) {
        _flashAnimationController.reverse();
      });

      final Directory extDir = await getTemporaryDirectory();
      final String dirPath = '${extDir.path}/Pictures';
      await Directory(dirPath).create(recursive: true);

      final String filePath =
          '$dirPath/${DateTime.now().millisecondsSinceEpoch}.jpg';

      final XFile picture = await _controller!.takePicture();
      final File imageFile = File(picture.path);
      await imageFile.copy(filePath);

      if (mounted) {
        setState(() {
          _capturedImage = File(filePath);
        });

        _showImagePreview();
      }
    } catch (e) {
      _showErrorSnackBar('Error taking picture: $e');
    }
  }

  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final Directory extDir = await getTemporaryDirectory();
      final String dirPath = '${extDir.path}/Videos';
      await Directory(dirPath).create(recursive: true);

      final String filePath =
          '$dirPath/${DateTime.now().millisecondsSinceEpoch}.mp4';

      await _controller!.startVideoRecording();

      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingDuration++;
          });
        }
      });
    } catch (e) {
      _showErrorSnackBar('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final XFile video = await _controller!.stopVideoRecording();
      _recordingTimer?.cancel();

      setState(() {
        _isRecording = false;
      });

      _showVideoSavedSnackBar(video.path);
    } catch (e) {
      _showErrorSnackBar('Error stopping recording: $e');
    }
  }

  void _showImagePreview() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            width: double.infinity,
            height: 400,
            child: _capturedImage != null
                ? Image.file(_capturedImage!, fit: BoxFit.cover)
                : const Center(child: Text('No image captured')),
          ),
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showVideoSavedSnackBar(String path) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Video saved to: $path'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isInitialized && _controller != null
            ? Stack(
                children: [
                  // Camera Preview - Rotates automatically with device
                  Positioned.fill(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: CameraPreview(_controller!),
                    ),
                  ),

                  // Flash animation overlay
                  AnimatedBuilder(
                    animation: _flashAnimationController,
                    builder: (context, child) {
                      return Container(
                        color: Colors.white.withOpacity(
                          _flashAnimationController.value * 0.5,
                        ),
                      );
                    },
                  ),

                  // Top Controls
                  Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 30,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Row(
                          children: [
                            // Flash toggle
                            IconButton(
                              icon: Icon(
                                _isFlashOn ? Icons.flash_on : Icons.flash_off,
                                color: Colors.white,
                                size: 30,
                              ),
                              onPressed: _toggleFlash,
                            ),
                            const SizedBox(width: 8),
                            // Camera switch
                            if (_cameras != null && _cameras!.length > 1)
                              IconButton(
                                icon: const Icon(
                                  Icons.flip_camera_ios,
                                  color: Colors.white,
                                  size: 30,
                                ),
                                onPressed: _toggleCamera,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Recording indicator
                  if (_isRecording)
                    Positioned(
                      top: 80,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDuration(_recordingDuration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Bottom Controls
                  Positioned(
                    bottom: 32,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        // Zoom slider
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Row(
                            children: [
                              const Icon(Icons.zoom_out, color: Colors.white),
                              Expanded(
                                child: Slider(
                                  value: _currentZoomLevel,
                                  min: 1.0,
                                  max: _maxZoomLevel,
                                  onChanged: (value) async {
                                    setState(() {
                                      _currentZoomLevel = value;
                                    });
                                    await _controller!.setZoomLevel(value);
                                  },
                                  activeColor: Colors.white,
                                ),
                              ),
                              const Icon(Icons.zoom_in, color: Colors.white),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Main capture controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Gallery preview
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: _capturedImage != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.file(
                                        _capturedImage!,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.photo,
                                      color: Colors.white,
                                    ),
                            ),

                            // Capture button
                            GestureDetector(
                              onTap: _isRecording ? null : _takePicture,
                              onLongPress: _isRecording
                                  ? null
                                  : _startRecording,
                              onLongPressUp: _stopRecording,
                              child: Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _isRecording
                                        ? Colors.red
                                        : Colors.white,
                                    width: 3,
                                  ),
                                ),
                                child: Container(
                                  margin: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _isRecording
                                        ? Colors.red
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),

                            // Resolution selector
                            PopupMenuButton<ResolutionPreset>(
                              icon: const Icon(
                                Icons.settings,
                                color: Colors.white,
                                size: 30,
                              ),
                              color: Colors.black87,
                              onSelected: (ResolutionPreset preset) async {
                                setState(() {
                                  _currentResolution = preset;
                                  _isInitialized = false;
                                });
                                await _initCameraController(
                                  _cameras![_isRearCamera ? 0 : 1],
                                );
                              },
                              itemBuilder: (BuildContext context) {
                                return ResolutionPreset.values.map((preset) {
                                  return PopupMenuItem(
                                    value: preset,
                                    child: Text(
                                      preset.toString().split('.').last,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  );
                                }).toList();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
      ),
    );
  }
}
