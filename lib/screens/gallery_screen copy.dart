import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/captured_image.dart';
import '../utils/storage_service.dart';
import '../widgets/image_card.dart';
import '../screens/full_screen_image_viewer.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Gallery',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        centerTitle: true,
        actions: [
          if (storageService.capturedImages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () {
                _shareAllImages(context);
              },
              tooltip: 'Share Images',
            ),
        ],
      ),
      body: storageService.capturedImages.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_library_rounded,
                    size: 80,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Gallery is empty',
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Capture some images first',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.8,
              ),
              itemCount: storageService.capturedImages.length,
              itemBuilder: (context, index) {
                final image = storageService.capturedImages[index];
                return ImageCard(
                  image: image,
                  onTap: () {
                    _showImagePreview(context, image);
                  },
                  onLongPress: () {
                    _showImageOptions(context, image);
                  },
                );
              },
            ),
    );
  }

  void _showImagePreview(BuildContext context, CapturedImage image) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImageViewer(image: image),
      ),
    );
  }

  void _showImageOptions(BuildContext context, CapturedImage image) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.remove_red_eye),
              title: const Text('Preview'),
              onTap: () {
                Navigator.pop(context);
                _showImagePreview(context, image);
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Save to Gallery'),
              onTap: () {
                Navigator.pop(context);
                _saveSingleImageToGallery(context, image);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                _shareSingleImage(context, image);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(context);
                _showDeleteDialog(context, image);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareAllImages(BuildContext context) async {
    final storageService = Provider.of<StorageService>(context, listen: false);
    final images = storageService.capturedImages;

    if (images.isEmpty) {
      _showSnackBar(context, 'No images to share', Colors.orange);
      return;
    }

    try {
      // Prepare files to share
      final files = <XFile>[];
      for (final image in images) {
        final file = File(image.imagePath);
        if (await file.exists()) {
          files.add(XFile(file.path));
        }
      }

      if (files.isEmpty) {
        _showSnackBar(context, 'No valid image files found', Colors.orange);
        return;
      }

      // Use share_plus package for sharing
      final result = await Share.shareXFiles(
        files,
        subject: 'Shared Images from Gallery',
        text: 'Check out these images captured from the app!',
      );

      if (result.status == ShareResultStatus.success) {
        _showSnackBar(context, 'Images shared successfully', Colors.green);
      }
    } catch (e) {
      _showSnackBar(context, 'Failed to share images: $e', Colors.red);
    }
  }

  Future<void> _shareSingleImage(
    BuildContext context,
    CapturedImage image,
  ) async {
    try {
      final file = File(image.imagePath);
      if (await file.exists()) {
        final xFile = XFile(file.path);
        final result = await Share.shareXFiles(
          [xFile],
          subject: 'Image from Gallery',
          text: 'Image captured at: ${image.timestamp}',
        );

        if (result.status == ShareResultStatus.success) {
          _showSnackBar(context, 'Image shared successfully', Colors.green);
        }
      } else {
        _showSnackBar(context, 'Image file not found', Colors.orange);
      }
    } catch (e) {
      _showSnackBar(context, 'Failed to share: $e', Colors.red);
    }
  }

  Future<void> _saveSingleImageToGallery(
    BuildContext context,
    CapturedImage image,
  ) async {
    try {
      final file = File(image.imagePath);
      if (await file.exists()) {
        // Save to gallery using image_gallery_saver
        final result = null;
        //await ImageGallerySaver.saveFile(file.path);

        if (result['isSuccess'] == true) {
          _showSnackBar(context, 'Image saved to gallery', Colors.green);
        } else {
          _showSnackBar(context, 'Failed to save image', Colors.orange);
        }
      } else {
        _showSnackBar(context, 'Image file not found', Colors.orange);
      }
    } on PlatformException catch (e) {
      _showSnackBar(context, 'Permission denied: $e', Colors.red);
    } catch (e) {
      _showSnackBar(context, 'Failed to save: $e', Colors.red);
    }
  }

  void _showDeleteDialog(BuildContext context, CapturedImage image) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text('Are you sure you want to delete this image?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final storageService = Provider.of<StorageService>(
                context,
                listen: false,
              );
              await storageService.deleteImage(image as String);
              Navigator.pop(context);
              _showSnackBar(context, 'Image deleted', Colors.red);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(
    BuildContext context,
    String message,
    Color backgroundColor,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
