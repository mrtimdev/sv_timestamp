// lib/screens/full_screen.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart'; // For root bundle
import '../constants/app_colors.dart';

class FullScreenGallery extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;
  final Function(AssetEntity)? onDelete;
  final Function(AssetEntity)? onShare;
  final Function(AssetEntity)? onSave;

  const FullScreenGallery({
    super.key,
    required this.assets,
    required this.initialIndex,
    this.onDelete,
    this.onShare,
    this.onSave,
  });

  @override
  State<FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<FullScreenGallery>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late PageController _pageController;
  late List<AssetEntity> _assets;
  late int _currentIndex;
  bool _showControls = true;
  bool _isDeleting = false;
  bool _isSharing = false;
  bool _isSaving = false;
  bool _isInitialized = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Zoom states for each image
  final Map<int, _ZoomState> _zoomStates = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Validate inputs
    if (widget.assets.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pop(context);
      });
      return;
    }

    _initializeGallery();
  }

  void _initializeGallery() {
    try {
      _assets = List.from(widget.assets); // Make a mutable copy
      _currentIndex = widget.initialIndex.clamp(0, _assets.length - 1);
      _pageController = PageController(initialPage: _currentIndex);

      _animationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
      _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
      );

      setState(() {
        _isInitialized = true;
      });

      // Preload adjacent images
      _preloadAdjacentImages(_currentIndex);
    } catch (e) {
      print('Error initializing gallery: $e');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showErrorAndPop('Failed to initialize gallery');
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes if needed
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _preloadAdjacentImages(int index) {
    // Preload next and previous images asynchronously
    if (index > 0 && index < _assets.length) {
      _assets[index - 1].file
          .then((file) {
            // File loaded, optionally cache
          })
          .catchError((e) {
            print('Error preloading previous image: $e');
          });
    }
    if (index < _assets.length - 1) {
      _assets[index + 1].file
          .then((file) {
            // File loaded, optionally cache
          })
          .catchError((e) {
            print('Error preloading next image: $e');
          });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _animationController.reverse();
      } else {
        _animationController.forward();
      }
    });
  }

  Future<void> _shareImage() async {
    final asset = _assets[_currentIndex];
    setState(() => _isSharing = true);

    try {
      File? imageFile = await asset.originFile;
      imageFile ??= await asset.file;

      if (imageFile == null) {
        throw Exception("Image file not accessible");
      }

      // Check if file exists
      if (!await imageFile.exists()) {
        throw Exception("Image file does not exist");
      }

      // Create temp file for sharing
      final cacheDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sharePath = '${cacheDir.path}/share_$timestamp.jpg';

      // Read bytes and write to temp file
      final bytes = await imageFile.readAsBytes();
      final shareFile = File(sharePath);
      await shareFile.writeAsBytes(bytes);

      // Verify temp file was created
      if (!await shareFile.exists()) {
        throw Exception("Failed to create share file");
      }

      final xFile = XFile(
        shareFile.path,
        mimeType: 'image/jpeg',
        name: 'image_$timestamp.jpg',
      );

      await Share.shareXFiles(
        [xFile],
        text: "Check out my photo!",
        sharePositionOrigin: Rect.fromLTWH(0, 0, 100, 100),
      );

      // Clean up temp file after sharing (with delay)
      Future.delayed(const Duration(seconds: 5), () {
        if (shareFile.existsSync()) {
          shareFile.deleteSync();
        }
      });

      if (widget.onShare != null) widget.onShare!(asset);
    } catch (e) {
      print('Share error: $e');
      _showSnackBar('Error sharing: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _saveImage() async {
    final asset = _assets[_currentIndex];
    setState(() => _isSaving = true);

    try {
      final file = await asset.file;
      if (file != null) {
        if (!await file.exists()) {
          throw Exception("File does not exist");
        }

        if (Platform.isIOS) {
          final result = await GallerySaver.saveImage(
            file.path,
            albumName: 'SVS-Watermark-Camera',
          );
          if (result == null || !result) {
            throw Exception("Failed to save to gallery");
          }
        } else {
          // For Android, use PhotoManager
          final bytes = await file.readAsBytes();
          final result = await PhotoManager.editor.saveImage(
            bytes,
            filename: file.path.split('/').last,
            title: file.path.split('/').last,
          );
          if (result == null) {
            throw Exception("Failed to save to gallery");
          }
        }

        _showSnackBar('Image saved to gallery');
        if (widget.onSave != null) widget.onSave!(asset);
      } else {
        throw Exception("Could not access image file");
      }
    } catch (e) {
      print('Save error: $e');
      _showSnackBar('Error saving: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteImage() async {
    final asset = _assets[_currentIndex];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text('Are you sure you want to delete this image?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isDeleting = true);

      try {
        final List<String> ids = [asset.id];
        final result = await PhotoManager.editor.deleteWithIds(ids);

        if (result.contains(asset.id)) {
          _showSnackBar('Image deleted successfully');

          if (widget.onDelete != null) widget.onDelete!(asset);

          // Remove the asset from the list
          setState(() {
            _assets.removeAt(_currentIndex);
          });

          // Handle navigation after deletion
          if (_assets.isEmpty) {
            // No more images, close the gallery
            Navigator.pop(context);
          } else {
            // Determine new index
            int newIndex = _currentIndex;
            if (newIndex >= _assets.length) {
              newIndex = _assets.length - 1;
            }

            // Animate to the new position
            _pageController.animateToPage(
              newIndex,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );

            // Update current index
            setState(() {
              _currentIndex = newIndex;
            });

            // Preload adjacent images for the new index
            _preloadAdjacentImages(newIndex);
          }
        } else {
          throw Exception('Failed to delete');
        }
      } catch (e) {
        print('Delete error: $e');
        _showSnackBar('Error deleting: ${e.toString()}', isError: true);
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorAndPop(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context);
  }

  String _formatDateDetailed(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = (log(bytes) / log(1024)).floor();
    double size = bytes / pow(1024, i);
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _assets.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppColors.primaryBlue),
              const SizedBox(height: 20),
              Text(
                'Loading gallery...',
                style: TextStyle(color: Colors.white.withAlpha(179)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main PageView with zoomable images
          PageView.builder(
            controller: _pageController,
            itemCount: _assets.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
                _showControls = true;
                _animationController.reverse();
              });
              _preloadAdjacentImages(index);
            },
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: _toggleControls,
                child: _ZoomableImage(
                  key: ValueKey('zoomable_${_assets[index].id}_$index'),
                  asset: _assets[index],
                  onZoomStateChanged: (state) {
                    _zoomStates[index] = state;
                  },
                ),
              );
            },
          ),

          // Top gradient bar with controls
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withAlpha(204), Colors.transparent],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      // Back button
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(102),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                      const Spacer(),

                      // Counter badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryBlue.withAlpha(102),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Text(
                          '${_currentIndex + 1}/${_assets.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom controls with image info
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withAlpha(204), Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionButton(
                            icon: Icons.share,
                            label: 'Share',
                            onTap: _shareImage,
                            isLoading: _isSharing,
                          ),
                          _buildActionButton(
                            icon: Icons.download,
                            label: 'Save',
                            onTap: _saveImage,
                            backgroundColor: AppColors.primaryBlue,
                            hasGlow: true,
                            isLoading: _isSaving,
                          ),
                          _buildActionButton(
                            icon: Icons.delete_outline,
                            label: 'Delete',
                            onTap: _deleteImage,
                            backgroundColor: Colors.red.withAlpha(179),
                            isLoading: _isDeleting,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),

          // Swipe down indicator (handle) - FIXED: Positioned must be direct child of Stack
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(153),
                      borderRadius: BorderRadius.circular(2),
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color backgroundColor = Colors.white,
    bool hasGlow = false,
    bool isLoading = false,
  }) {
    final Color bgColor = isLoading
        ? backgroundColor.withAlpha(102)
        : backgroundColor.withAlpha(179);
    final Color iconColor = backgroundColor == Colors.white
        ? Colors.black87
        : Colors.white;

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withAlpha(51), width: 1),
          boxShadow: hasGlow && !isLoading
              ? [
                  BoxShadow(
                    color: AppColors.primaryBlue.withAlpha(102),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    backgroundColor == Colors.white
                        ? Colors.black87
                        : Colors.white,
                  ),
                ),
              )
            else
              Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Text(
              isLoading ? '...' : label,
              style: TextStyle(
                color: iconColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Separate widget for zoomable image
class _ZoomableImage extends StatefulWidget {
  final AssetEntity asset;
  final Function(_ZoomState) onZoomStateChanged;

  const _ZoomableImage({
    super.key,
    required this.asset,
    required this.onZoomStateChanged,
  });

  @override
  State<_ZoomableImage> createState() => __ZoomableImageState();
}

class __ZoomableImageState extends State<_ZoomableImage> {
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _isLoading = true;
  bool _hasError = false;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _loadImage();
    _transformationController.addListener(_onZoomChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onZoomChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onZoomChanged() {
    final state = _ZoomState(
      isZoomed: _transformationController.value != Matrix4.identity(),
      scale: _transformationController.value.getMaxScaleOnAxis(),
    );
    widget.onZoomStateChanged(state);
  }

  Future<void> _loadImage() async {
    try {
      final file = await widget.asset.file;
      if (mounted) {
        setState(() {
          _imageFile = file;
          _isLoading = false;
          _hasError = file == null;
        });
      }
    } catch (e) {
      print('Error loading image: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition;
      _transformationController.value = Matrix4.identity()
        ..translate(-(position?.dx ?? 0) * 2, -(position?.dy ?? 0) * 2)
        ..scale(3.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(26),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryBlue,
                  strokeWidth: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading image...',
              style: TextStyle(
                color: Colors.white.withAlpha(179),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_hasError || _imageFile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(26),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.broken_image,
                size: 40,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load image',
              style: TextStyle(
                color: Colors.white.withAlpha(179),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      child: Center(
        child: InteractiveViewer(
          transformationController: _transformationController,
          minScale: 0.5,
          maxScale: 4.0,
          panEnabled: true,
          scaleEnabled: true,
          boundaryMargin: const EdgeInsets.all(20),
          clipBehavior: Clip.none,
          child: Hero(
            tag: 'fullscreen_${widget.asset.id}',
            child: Image.file(
              _imageFile!,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[900],
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, size: 50, color: Colors.grey),
                        SizedBox(height: 10),
                        Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomState {
  final bool isZoomed;
  final double scale;

  _ZoomState({required this.isZoomed, required this.scale});
}
