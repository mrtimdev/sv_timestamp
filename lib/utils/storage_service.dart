import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/captured_image.dart';
import 'metadata_service.dart';

class StorageService extends ChangeNotifier {
  List<CapturedImage> _capturedImages = [];
  List<CapturedImage> get capturedImages => _capturedImages;

  static const String _capturedImagesKey = 'captured_images';

  StorageService() {
    _loadImages();
  }

  // Load captured images from shared preferences
  Future<void> loadCapturedImages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? imagesJson = prefs.getString(_capturedImagesKey);

      if (imagesJson != null) {
        final List<dynamic> decoded = json.decode(imagesJson);
        _capturedImages =
            decoded.map((item) => CapturedImage.fromJson(item)).toList();

        // Verify files still exist and remove invalid entries
        _capturedImages.removeWhere((image) {
          final exists = File(image.imagePath).existsSync();
          if (!exists) {
            print('Removing invalid image: ${image.imagePath}');
          }
          return !exists;
        });

        notifyListeners();
      }
    } catch (e) {
      print('Error loading captured images: $e');
      _capturedImages = [];
    }
  }

  // Save captured images to shared preferences
  Future<void> saveCapturedImages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> jsonList =
          _capturedImages.map((image) => image.toJson()).toList();
      await prefs.setString(_capturedImagesKey, json.encode(jsonList));
    } catch (e) {
      print('Error saving captured images: $e');
    }
  }

  // Add a new captured image
  Future<void> addCapturedImage(CapturedImage image) async {
    _capturedImages.insert(0, image);
    await saveCapturedImages();
    notifyListeners();
  }

  // Remove a captured image
  Future<void> removeCapturedImage(String id) async {
    final index = _capturedImages.indexWhere((img) => img.id == id);
    if (index != -1) {
      final image = _capturedImages[index];

      // Delete the actual files
      try {
        if (await File(image.imagePath).exists()) {
          await File(image.imagePath).delete();
        }
        if (image.originalPath != null &&
            await File(image.originalPath!).exists()) {
          await File(image.originalPath!).delete();
        }
      } catch (e) {
        print('Error deleting image files: $e');
      }

      _capturedImages.removeAt(index);
      await saveCapturedImages();
      notifyListeners();
    }
  }

  // Clear all captured images
  Future<void> clearAllImages() async {
    // Delete all files
    for (var image in _capturedImages) {
      try {
        if (await File(image.imagePath).exists()) {
          await File(image.imagePath).delete();
        }
        if (image.originalPath != null &&
            await File(image.originalPath!).exists()) {
          await File(image.originalPath!).delete();
        }
      } catch (e) {
        print('Error deleting image files: $e');
      }
    }

    _capturedImages.clear();
    await saveCapturedImages();
    notifyListeners();
  }

  // Get image count
  int get imageCount => _capturedImages.length;

  // Check if has images
  bool get hasImages => _capturedImages.isNotEmpty;

  // Get image by id
  CapturedImage? getImageById(String id) {
    try {
      return _capturedImages.firstWhere((img) => img.id == id);
    } catch (e) {
      return null;
    }
  }

  // Get latest image
  CapturedImage? get latestImage {
    return _capturedImages.isNotEmpty ? _capturedImages.first : null;
  }

  // Update image data
  Future<void> updateImage(CapturedImage updatedImage) async {
    final index =
        _capturedImages.indexWhere((img) => img.id == updatedImage.id);
    if (index != -1) {
      _capturedImages[index] = updatedImage;
      await saveCapturedImages();
      notifyListeners();
    }
  }

  // Load images from file system
  Future<void> _loadImages() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir =
          Directory(path.join(appDir.path, 'captured_images', 'watermarked'));

      if (await imagesDir.exists()) {
        final files = imagesDir.listSync();
        final imageFiles = files.whereType<File>().toList();

        for (final file in imageFiles) {
          final fileName = path.basename(file.path);
          // Parse filename: IMG_1234567890.jpg
          final regex = RegExp(r'IMG_(\d+)\.jpg');
          final match = regex.firstMatch(fileName);

          if (match != null) {
            final timestampMs = int.parse(match.group(1)!);
            final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);

            // Check if image already exists in list
            final exists =
                _capturedImages.any((img) => img.imagePath == file.path);

            if (!exists) {
              _capturedImages.add(
                CapturedImage(
                  id: timestampMs.toString(),
                  imagePath: file.path,
                  timestamp: timestamp,
                  location: null,
                  address: null,
                  originalPath: null,
                  additionalData: {'loaded_from_storage': true},
                ),
              );
            }
          }
        }

        // Sort by timestamp descending (newest first)
        _capturedImages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading images: $e');
    }
  }

  // Capture image from camera (legacy method)
  Future<CapturedImage?> captureImage() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return null;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          debugPrint('Location permission denied.');
          return null;
        }
      }

      // Capture image from camera
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 90,
      );

      if (image == null) return null;

      // Get metadata
      final timestamp = DateTime.now();
      final location = await MetadataService.getCurrentLocation();
      String? address;

      if (location != null) {
        address = await MetadataService.getAddressFromCoordinates(
          location['latitude']!,
          location['longitude']!,
        );
      }

      // Read original image
      final originalBytes = await File(image.path).readAsBytes();

      // Add metadata to image
      final processedBytes = await MetadataService.addMetadataToImage(
        originalBytes,
        timestamp,
        location,
        address,
      );

      // Save processed image
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'IMG_${timestamp.millisecondsSinceEpoch}.jpg';
      final savedPath =
          path.join(appDir.path, 'captured_images', 'watermarked', fileName);

      await Directory(path.dirname(savedPath)).create(recursive: true);
      await File(savedPath).writeAsBytes(processedBytes);

      // Create captured image object
      final capturedImage = CapturedImage(
        id: timestamp.millisecondsSinceEpoch.toString(),
        imagePath: savedPath,
        timestamp: timestamp,
        location: location,
        address: address,
        additionalData: {'device': 'Mobile', 'app': 'SV'},
      );

      _capturedImages.insert(0, capturedImage);
      await saveCapturedImages();
      notifyListeners();

      return capturedImage;
    } catch (e) {
      debugPrint('Error capturing image: $e');
      return null;
    }
  }

  // Delete image by id
  Future<void> deleteImage(String id) async {
    await removeCapturedImage(id);
  }

  // Get total storage size
  Future<int> getTotalStorageSize() async {
    try {
      int totalSize = 0;

      // Get the directory where images are stored
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(path.join(appDir.path, 'captured_images'));

      // Check if directory exists
      if (await imagesDir.exists()) {
        // Recursively list all files
        final files = await _listFilesRecursively(imagesDir);

        for (var file in files) {
          try {
            final stat = await file.stat();
            totalSize += stat.size;
          } catch (e) {
            print('Error getting file size for ${file.path}: $e');
          }
        }
      }

      return totalSize;
    } catch (e) {
      print('Error calculating storage size: $e');
      return 0;
    }
  }

  // Helper method to list files recursively
  Future<List<File>> _listFilesRecursively(Directory dir) async {
    List<File> files = [];
    try {
      final entities = await dir.list().toList();
      for (var entity in entities) {
        if (entity is File) {
          files.add(entity);
        } else if (entity is Directory) {
          files.addAll(await _listFilesRecursively(entity));
        }
      }
    } catch (e) {
      print('Error listing files: $e');
    }
    return files;
  }

  /// Delete all captured images from storage and memory
  Future<void> deleteAllImages() async {
    try {
      // Get the directory where images are stored
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(path.join(appDir.path, 'captured_images'));

      // Check if directory exists
      if (await imagesDir.exists()) {
        // Delete all files in the directory
        final files = await _listFilesRecursively(imagesDir);

        for (var file in files) {
          try {
            await file.delete();
          } catch (e) {
            print('Error deleting file ${file.path}: $e');
          }
        }
      }

      // Clear the in-memory list
      _capturedImages.clear();
      await saveCapturedImages();
      notifyListeners();
    } catch (e) {
      print('Error deleting all images: $e');
      throw Exception('Failed to delete all images: $e');
    }
  }

  /// Alternative: Delete images one by one from capturedImages list
  Future<void> deleteAllImagesFromList() async {
    try {
      // Make a copy of the list to avoid modification during iteration
      final imagesToDelete = List<CapturedImage>.from(_capturedImages);

      for (var image in imagesToDelete) {
        try {
          // Delete the file
          final file = File(image.imagePath);
          if (await file.exists()) {
            await file.delete();
          }

          // Delete original if exists
          if (image.originalPath != null &&
              await File(image.originalPath!).exists()) {
            await File(image.originalPath!).delete();
          }

          // Remove from list
          _capturedImages.removeWhere((img) => img.id == image.id);
        } catch (e) {
          print('Error deleting image ${image.id}: $e');
          // Continue with next image even if one fails
        }
      }

      await saveCapturedImages();
      notifyListeners();
    } catch (e) {
      print('Error in deleteAllImagesFromList: $e');
      throw Exception('Failed to delete images: $e');
    }
  }

  /// Get formatted storage information
  Future<Map<String, dynamic>> getStorageInfo() async {
    try {
      final totalSize = await getTotalStorageSize();
      final imageCount = _capturedImages.length;

      return {
        'totalSize': totalSize,
        'formattedSize': _formatBytes(totalSize),
        'imageCount': imageCount,
        'averageSize': imageCount > 0 ? totalSize ~/ imageCount : 0,
      };
    } catch (e) {
      print('Error getting storage info: $e');
      return {
        'totalSize': 0,
        'formattedSize': '0 B',
        'imageCount': 0,
        'averageSize': 0,
      };
    }
  }

  /// Format bytes to human readable format
  String _formatBytes(int bytes, {int decimals = 2}) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }
}
