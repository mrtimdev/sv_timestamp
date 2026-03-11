import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:sv_timestamp/constants/app_colors.dart';
import '../models/captured_image.dart';
import '../utils/storage_service.dart';
import 'package:provider/provider.dart';

class FullScreenImageViewer extends StatefulWidget {
  final CapturedImage image;
  final bool showOriginal; // New parameter

  const FullScreenImageViewer({
    super.key,
    required this.image,
    this.showOriginal = false, // Default to watermarked
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer>
    with SingleTickerProviderStateMixin {
  late bool _isShowingOriginal;
  late AnimationController _toggleAnimController;
  late Animation<double> _fadeAnimation;
  bool _showControls = true;
  String? _currentImagePath;

  @override
  void initState() {
    super.initState();
    _isShowingOriginal = widget.showOriginal;
    _currentImagePath = _getCurrentImagePath();

    _toggleAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _toggleAnimController, curve: Curves.easeIn),
    );

    _toggleAnimController.forward();
  }

  String _getCurrentImagePath() {
    if (_isShowingOriginal && widget.image.originalPath != null) {
      return widget.image.originalPath!;
    }
    return widget.image.imagePath;
  }

  void _toggleImageVersion() {
    if (widget.image.originalPath == null) {
      _showSnackBar(context, 'Original image not available', Colors.orange);
      return;
    }

    _toggleAnimController.reset();
    setState(() {
      _isShowingOriginal = !_isShowingOriginal;
      _currentImagePath = _getCurrentImagePath();
    });
    _toggleAnimController.forward();

    _showSnackBar(
      context,
      _isShowingOriginal
          ? 'Showing original image'
          : 'Showing watermarked image',
      Colors.blue,
      duration: const Duration(milliseconds: 800),
    );
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Image Viewer
          GestureDetector(
            onTap: _toggleControls,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: FadeTransition(
                key: ValueKey<String>(_currentImagePath!),
                opacity: _fadeAnimation,
                child: PhotoView(
                  imageProvider: FileImage(File(_currentImagePath!)),
                  backgroundDecoration: const BoxDecoration(
                    color: Colors.black,
                  ),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3,
                  initialScale: PhotoViewComputedScale.contained,
                  heroAttributes: PhotoViewHeroAttributes(
                    tag: widget.image.imagePath,
                    transitionOnUserGestures: true,
                  ),
                  loadingBuilder: (context, event) => Center(
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image,
                            color: Colors.grey[600],
                            size: 80,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Top Bar (animated visibility)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showControls
                ? 0
                : -kToolbarHeight - MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: _buildAppBar(),
          ),

          // Bottom Bar (animated visibility)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showControls ? 0 : -100,
            left: 0,
            right: 0,
            child: _buildBottomBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 8,
        right: 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.8), Colors.transparent],
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Back button with cool effect
            _buildIconButton(
              icon: Icons.arrow_back_ios_new,
              onPressed: () => Navigator.pop(context),
              tooltip: 'Back',
            ),

            // Center title with date
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDate(widget.image.timestamp),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(widget.image.timestamp),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Toggle button (original/watermarked)
            if (widget.image.originalPath != null)
              _buildIconButton(
                icon: _isShowingOriginal ? Icons.water_drop : Icons.image,
                onPressed: _toggleImageVersion,
                tooltip: _isShowingOriginal
                    ? 'Show watermarked'
                    : 'Show original',
                color: _isShowingOriginal ? Colors.orange : Colors.blue,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.8), Colors.transparent],
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionButton(
              icon: Icons.share,
              label: 'Share',
              onPressed: () => _shareImage(context as AssetEntity),
            ),
            _buildActionButton(
              icon: Icons.save_alt,
              label: 'Save',
              onPressed: () => _saveImageToGallery(context),
            ),
            _buildActionButton(
              icon: Icons.info_outline,
              label: 'Info',
              onPressed: () => _showImageDetails(context),
            ),
            _buildActionButton(
              icon: Icons.more_vert,
              label: 'More',
              onPressed: () => _showMoreOptions(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
    Color color = Colors.white,
  }) {
    return Container(
      decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icon, color: color),
        onPressed: onPressed,
        tooltip: tooltip,
        splashRadius: 24,
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final amPm = date.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} $amPm';
  }

  Future<void> _shareImage(AssetEntity asset) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );

      // Try different methods to get the file
      File? fileToShare;

      // Method 1: Try origin file (best quality)
      fileToShare = await asset.originFile;

      // Method 2: Try regular file
      if (fileToShare == null) {
        fileToShare = await asset.file;
      }

      // Method 3: Try thumbnail as last resort
      if (fileToShare == null) {
        final thumbnailData = await asset.thumbnailDataWithSize(
          const ThumbnailSize(1024, 1024),
        );
        if (thumbnailData != null) {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/temp_${asset.id}.jpg');
          await tempFile.writeAsBytes(thumbnailData);
          fileToShare = tempFile;
        }
      }

      // Close loading dialog
      Navigator.pop(context);

      if (fileToShare != null && await fileToShare.exists()) {
        if (Platform.isIOS) {
          // For iOS, always use a temporary file in a shared location
          final tempDir = await getTemporaryDirectory();
          final uniqueName =
              'share_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final tempFile = File('${tempDir.path}/$uniqueName');

          // Copy to temp location
          await tempFile.writeAsBytes(await fileToShare.readAsBytes());

          // Verify file exists and is readable
          if (await tempFile.exists()) {
            // Share from temp location
            final result = await Share.shareXFiles([
              XFile(tempFile.path),
            ], text: 'Check out my photo!');

            // Clean up temp file after sharing completes
            tempFile.delete();
          }
        } else {
          // Android - share directly
          await Share.shareXFiles([
            XFile(fileToShare.path),
          ], text: 'Check out my photo!');
        }
      } else {
        throw Exception('Could not access image file');
      }
    } catch (e) {
      // Close loading dialog if open
      if (mounted) {
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not share image'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      print('Share error: $e');
    }
  }

  String _getShareText() {
    final type = _isShowingOriginal ? 'Original' : 'Watermarked';
    return '''
$type Image from SV TimeStamp
📅 ${_formatDate(widget.image.timestamp)} at ${_formatTime(widget.image.timestamp)}
📍 ${widget.image.location != null ? '${widget.image.location!['latitude']!.toStringAsFixed(4)}, ${widget.image.location!['longitude']!.toStringAsFixed(4)}' : 'No location'}
🏠 ${widget.image.address ?? 'No address'}
    ''';
  }

  Future<void> _saveImageToGallery(BuildContext context) async {
    try {
      final file = File(_currentImagePath!);
      if (await file.exists()) {
        final result = await GallerySaver.saveImage(file.path);

        if (result == true) {
          _showSnackBar(context, 'Image saved to gallery', Colors.green);
        } else {
          _showSnackBar(context, 'Failed to save image', Colors.orange);
        }
      } else {
        _showSnackBar(context, 'Image file not found', Colors.orange);
      }
    } on PlatformException catch (e) {
      _showSnackBar(
        context,
        'Permission denied: Please grant storage permission',
        Colors.red,
      );
    } catch (e) {
      _showSnackBar(context, 'Failed to save: $e', Colors.red);
    }
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            if (widget.image.originalPath != null)
              ListTile(
                leading: Icon(
                  _isShowingOriginal ? Icons.water_drop : Icons.image,
                  color: _isShowingOriginal ? Colors.orange : Colors.blue,
                ),
                title: Text(
                  _isShowingOriginal
                      ? 'Switch to Watermarked'
                      : 'Switch to Original',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _toggleImageVersion();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Delete Image',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteImage(context);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _deleteImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text(
          'Are you sure you want to delete this image? This action cannot be undone.',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              try {
                // Delete watermarked image
                final watermarkedFile = File(widget.image.imagePath);
                if (watermarkedFile.existsSync()) {
                  watermarkedFile.deleteSync();
                }

                // Delete original image if exists
                if (widget.image.originalPath != null) {
                  final originalFile = File(widget.image.originalPath!);
                  if (originalFile.existsSync()) {
                    originalFile.deleteSync();
                  }
                }

                // Remove from storage
                final storage = Provider.of<StorageService>(
                  context,
                  listen: false,
                );
                storage.capturedImages.removeWhere(
                  (img) => img.id == widget.image.id,
                );

                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Go back

                _showSnackBar(context, 'Image deleted', Colors.orange);
              } catch (e) {
                Navigator.pop(context);
                _showSnackBar(context, 'Failed to delete: $e', Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showImageDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  _isShowingOriginal ? Icons.image : Icons.water_drop,
                  color: _isShowingOriginal ? Colors.orange : Colors.blue,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  'Image Details',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailItem(
              context,
              Icons.access_time,
              'Captured Time',
              '${_formatDate(widget.image.timestamp)} at ${_formatTime(widget.image.timestamp)}',
            ),
            if (widget.image.location != null)
              _buildDetailItem(
                context,
                Icons.location_on,
                'GPS Coordinates',
                '${widget.image.location!['latitude']!.toStringAsFixed(6)}, '
                    '${widget.image.location!['longitude']!.toStringAsFixed(6)}',
              ),
            if (widget.image.address != null)
              _buildDetailItem(
                context,
                Icons.place,
                'Address',
                widget.image.address!,
              ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(
    BuildContext context,
    IconData icon,
    String title,
    String value,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(
    BuildContext context,
    String message,
    Color backgroundColor, {
    Duration duration = const Duration(seconds: 2),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  void dispose() {
    _toggleAnimController.dispose();
    super.dispose();
  }
}
