// lib/screens/gallery_screen.dart (updated with checkbox selection)
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path/path.dart' as path;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sv_timestamp/screens/new_custom_camera.dart';
import '../constants/app_colors.dart';
import 'full_screen.dart'; // Import the new full screen

class GalleryScreen extends StatefulWidget {
  final AssetEntity? initialAsset;

  const GalleryScreen({super.key, this.initialAsset});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  // Grouped assets by date
  Map<String, List<AssetEntity>> _groupedAssets = {};
  List<String> _dateGroups = [];
  bool _isLoading = true;
  bool _isDeleting = false;
  bool _hasPermission = false;
  String? _selectedAssetId;

  // Selected images for multi-select
  Set<String> _selectedAssetIds = {};
  bool _isSelectionMode = false;

  // Selected image index for preview (global index)
  int? _selectedImageIndex;

  // Pagination
  int _currentPage = 0;
  final int _pageSize = 50;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();

  // Album reference
  AssetPathEntity? _targetAlbum;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionAndLoad();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload when returning to screen
    if (_hasPermission) {
      _refreshGallery();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _hasPermission) {
      _refreshGallery();
    }
  }

  // Platform-specific permission handling
  Future<bool> _requestPermissions() async {
    if (Platform.isIOS) {
      // iOS permission handling
      final photos = await Permission.photos.request();
      final limited = await Permission.photosAddOnly.request();

      if (photos.isGranted || photos.isLimited) {
        return true;
      }

      // Try PhotoManager permission for iOS
      final pmPerm = await PhotoManager.requestPermissionExtend();
      return pmPerm.isAuth || pmPerm.hasAccess;
    } else if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      // Android 13+ (API 33+)
      if (androidInfo.version.sdkInt >= 33) {
        final photos = await Permission.photos.request();
        final videos = await Permission.videos.request();
        final audio = await Permission.audio.request();

        return photos.isGranted ||
            photos.isLimited ||
            (videos.isGranted && audio.isGranted);
      }
      // Android 10-12 (API 29-32)
      else if (androidInfo.version.sdkInt >= 29) {
        final storage = await Permission.storage.request();
        final manageStorage = await Permission.manageExternalStorage.request();

        return storage.isGranted || manageStorage.isGranted;
      }
      // Android 9 and below (API 28 and below)
      else {
        final storage = await Permission.storage.request();
        return storage.isGranted;
      }
    }

    return false;
  }

  Future<void> _checkPermissionAndLoad() async {
    setState(() => _isLoading = true);

    // Request permissions using platform-specific approach
    bool permissionGranted = await _requestPermissions();

    // Also check PhotoManager permission
    final photoManagerPerm = await PhotoManager.requestPermissionExtend();
    permissionGranted =
        permissionGranted ||
        photoManagerPerm.isAuth ||
        photoManagerPerm.hasAccess;

    if (permissionGranted) {
      setState(() => _hasPermission = true);
      await _loadTargetAlbum();
      await _loadImages(reset: true);

      // If there's an initial asset, find its index and show preview
      if (widget.initialAsset != null && mounted) {
        _findAndShowInitialAsset();
      }
    } else {
      setState(() {
        _hasPermission = false;
        _isLoading = false;
      });

      // Show permission dialog
      _showPermissionDialog();
    }
  }

  Future<void> _loadTargetAlbum() async {
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
      );

      // Find our app's album
      for (var album in albums) {
        if (album.name == 'SV-Watermark-Camera') {
          _targetAlbum = album;
          break;
        }
      }

      // If not found, get the recent album or create one
      if (_targetAlbum == null && albums.isNotEmpty) {
        // Try to get the "Recent" or "All" album
        _targetAlbum = albums.firstWhere(
          (album) =>
              album.isAll ||
              album.name.toLowerCase().contains('recent') ||
              album.name.toLowerCase().contains('camera'),
          orElse: () => albums.first,
        );
      }
    } catch (e) {
      print('Error loading album: $e');
    }
  }

  Future<void> _refreshGallery() async {
    setState(() {
      _currentPage = 0;
      _hasMore = true;
      _groupedAssets = {};
      _dateGroups = [];
      _selectedAssetIds.clear();
      _isSelectionMode = false;
    });
    await _loadTargetAlbum();
    await _loadImages(reset: true);
  }

  // Group assets by date
  void _groupAssetsByDate(List<AssetEntity> assets) {
    _groupedAssets = {};

    for (var asset in assets) {
      String dateKey = _getDateKey(asset.createDateTime);

      if (_groupedAssets.containsKey(dateKey)) {
        _groupedAssets[dateKey]!.add(asset);
      } else {
        _groupedAssets[dateKey] = [asset];
      }
    }

    // Sort dates in descending order (newest first)
    _dateGroups = _groupedAssets.keys.toList()
      ..sort((a, b) {
        DateTime dateA = _parseDateKey(a);
        DateTime dateB = _parseDateKey(b);
        return dateB.compareTo(dateA);
      });

    // Sort assets within each group by date (newest first)
    for (var dateKey in _dateGroups) {
      _groupedAssets[dateKey]!.sort(
        (a, b) => b.createDateTime.compareTo(a.createDateTime),
      );
    }
  }

  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  DateTime _parseDateKey(String dateKey) {
    var parts = dateKey.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  String _formatGroupDate(String dateKey) {
    DateTime date = _parseDateKey(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final assetDate = DateTime(date.year, date.month, date.day);

    if (assetDate == today) {
      return 'Today';
    } else if (assetDate == yesterday) {
      return 'Yesterday';
    } else {
      // Check if it's within the last 7 days
      final difference = today.difference(assetDate).inDays;
      if (difference < 7) {
        return _getDayName(date.weekday);
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    }
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  // Get global index from group and local index
  int _getGlobalIndex(String groupKey, int localIndex) {
    int globalIndex = 0;
    for (var key in _dateGroups) {
      if (key == groupKey) {
        return globalIndex + localIndex;
      }
      globalIndex += _groupedAssets[key]!.length;
    }
    return 0;
  }

  // Get group and local index from global index
  MapEntry<String, int>? _getGroupAndLocalIndex(int globalIndex) {
    int counter = 0;
    for (var groupKey in _dateGroups) {
      int groupSize = _groupedAssets[groupKey]!.length;
      if (globalIndex < counter + groupSize) {
        return MapEntry(groupKey, globalIndex - counter);
      }
      counter += groupSize;
    }
    return null;
  }

  Future<void> _loadImages({bool reset = false}) async {
    if (!_hasPermission || _targetAlbum == null) return;

    if (reset) {
      _currentPage = 0;
      _hasMore = true;
    }

    if (!_hasMore || _isLoadingMore) return;

    try {
      setState(() {
        if (reset) {
          _isLoading = true;
        } else {
          _isLoadingMore = true;
        }
      });

      // Fetch assets with pagination
      final assets = await _targetAlbum!.getAssetListPaged(
        page: _currentPage,
        size: _pageSize,
      );

      // Filter for images only
      final imageAssets = assets
          .where((asset) => asset.type == AssetType.image)
          .toList();

      _hasMore = assets.length == _pageSize;
      if (_hasMore) _currentPage++;

      setState(() {
        if (reset) {
          // Get all assets and group them
          List<AssetEntity> allAssets = [...imageAssets];
          _groupAssetsByDate(allAssets);
        } else {
          // Add to existing assets
          List<AssetEntity> allAssets = [];
          for (var group in _groupedAssets.values) {
            allAssets.addAll(group);
          }
          allAssets.addAll(imageAssets);
          _groupAssetsByDate(allAssets);
        }
        _isLoading = false;
        _isLoadingMore = false;
      });

      print(
        'Gallery loaded with ${_groupedAssets.values.expand((e) => e).length} images in ${_dateGroups.length} groups',
      );
    } catch (e) {
      print('Error loading images: $e');
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _findAndShowInitialAsset() async {
    if (widget.initialAsset == null) return;

    // Get all assets flattened
    List<AssetEntity> allAssets = _groupedAssets.values
        .expand((e) => e)
        .toList();

    // Find the index
    int globalIndex = allAssets.indexWhere(
      (asset) => asset.id == widget.initialAsset!.id,
    );

    if (globalIndex != -1) {
      // Found in current loaded assets
      _selectedImageIndex = globalIndex;
      _navigateToFullScreen(globalIndex);
    } else {
      // Need to load more pages to find it
      bool found = false;
      while (_hasMore && !found && mounted) {
        await _loadImages();

        allAssets = _groupedAssets.values.expand((e) => e).toList();
        globalIndex = allAssets.indexWhere(
          (asset) => asset.id == widget.initialAsset!.id,
        );

        if (globalIndex != -1) {
          found = true;
          _selectedImageIndex = globalIndex;

          // Scroll to the image
          _scrollToAsset(globalIndex);

          // Navigate to full screen after a short delay
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _navigateToFullScreen(globalIndex);
            }
          });
        }
      }

      if (!found && mounted) {
        // Asset not found in gallery
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Image not found in gallery'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _scrollToAsset(int globalIndex) {
    if (_scrollController.hasClients) {
      // Find which group this asset belongs to
      int groupIndex = 0;
      int counter = 0;

      for (var groupKey in _dateGroups) {
        int groupSize = _groupedAssets[groupKey]!.length;
        if (globalIndex < counter + groupSize) {
          // Found the group, now calculate scroll position
          const crossAxisCount = 3;
          final rowInGroup = (globalIndex - counter) ~/ crossAxisCount;

          // Add header height for each previous group
          int totalRows = 0;
          for (int i = 0; i < groupIndex; i++) {
            int groupRows =
                (_groupedAssets[_dateGroups[i]]!.length / crossAxisCount)
                    .ceil();
            totalRows += groupRows + 1; // +1 for group header
          }
          totalRows += rowInGroup;

          final position =
              totalRows * 140.0; // Approximate row height with header

          _scrollController.animateTo(
            position,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
          break;
        }
        counter += groupSize;
        groupIndex++;
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadImages();
    }
  }

  // Handle image tap - either select or view
  void _handleImageTap(AssetEntity asset, int globalIndex) {
    if (_isSelectionMode) {
      _toggleSelection(asset.id);
    } else {
      _navigateToFullScreen(globalIndex);
    }
  }

  // Handle long press - enter selection mode
  void _handleImageLongPress(String assetId) {
    if (!_isSelectionMode) {
      setState(() {
        _isSelectionMode = true;
        _selectedAssetIds.add(assetId);
      });
    }
  }

  // Toggle selection for an asset
  void _toggleSelection(String assetId) {
    setState(() {
      if (_selectedAssetIds.contains(assetId)) {
        _selectedAssetIds.remove(assetId);
        if (_selectedAssetIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedAssetIds.add(assetId);
      }
    });
  }

  // Navigate to full screen gallery
  void _navigateToFullScreen(int initialIndex) {
    List<AssetEntity> allAssets = _groupedAssets.values
        .expand((e) => e)
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenGallery(
          assets: allAssets,
          initialIndex: initialIndex,
          onDelete: (deletedAsset) {
            // Handle deletion - refresh gallery
            _refreshGallery();
          },
          onShare: (sharedAsset) {
            // Optional: track shares
            print('Shared: ${sharedAsset.id}');
          },
          onSave: (savedAsset) {
            // Optional: track saves
            print('Saved: ${savedAsset.id}');
          },
        ),
      ),
    );
  }

  // Delete selected images
  Future<void> _deleteSelectedImages() async {
    if (_selectedAssetIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_selectedAssetIds.length} Images'),
        content: Text(
          'Are you sure you want to delete ${_selectedAssetIds.length} image${_selectedAssetIds.length > 1 ? 's' : ''}?',
        ),
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
        final List<String> ids = _selectedAssetIds.toList();
        final result = await PhotoManager.editor.deleteWithIds(ids);

        if (result.isNotEmpty) {
          // Refresh gallery
          await _refreshGallery();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${result.length} image${result.length > 1 ? 's' : ''} deleted',
                ),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } catch (e) {
        print('Error deleting: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting images: $e'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isDeleting = false;
            _selectedAssetIds.clear();
            _isSelectionMode = false;
          });
        }
      }
    }
  }

  // Share selected images
  Future<void> _shareSelectedImages() async {
    if (_selectedAssetIds.isEmpty) return;

    setState(() => _isDeleting = true); // Reuse for loading indicator

    try {
      List<AssetEntity> allAssets = _groupedAssets.values
          .expand((e) => e)
          .toList();

      final selectedAssets = allAssets
          .where((asset) => _selectedAssetIds.contains(asset.id))
          .toList();

      List<XFile> xFiles = [];

      for (var asset in selectedAssets) {
        File? imageFile = await asset.originFile;
        imageFile ??= await asset.file;

        if (imageFile != null) {
          // Create temp files for sharing
          final cacheDir = await getTemporaryDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final sharePath = '${cacheDir.path}/share_$timestamp.jpg';

          final bytes = await imageFile.readAsBytes();
          final shareFile = File(sharePath);
          await shareFile.writeAsBytes(bytes);

          xFiles.add(
            XFile(
              shareFile.path,
              mimeType: 'image/jpeg',
              name: 'image_$timestamp.jpg',
            ),
          );
        }
      }

      if (xFiles.isNotEmpty) {
        await Share.shareXFiles(
          xFiles,
          text: "Check out my photos!",
          sharePositionOrigin: Rect.fromLTWH(0, 0, 100, 100),
        );

        // Clean up temp files after sharing
        Future.delayed(const Duration(seconds: 5), () {
          for (var file in xFiles) {
            File(file.path).deleteSync();
          }
        });
      }

      // Exit selection mode after sharing
      setState(() {
        _selectedAssetIds.clear();
        _isSelectionMode = false;
      });
    } catch (e) {
      print("Share error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not share images: ${e.toString()}"),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // Clear selection
  void _clearSelection() {
    setState(() {
      _selectedAssetIds.clear();
      _isSelectionMode = false;
    });
  }

  // Select all images
  void _selectAll() {
    List<AssetEntity> allAssets = _groupedAssets.values
        .expand((e) => e)
        .toList();

    setState(() {
      _selectedAssetIds = allAssets.map((e) => e.id).toSet();
    });
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Please grant photo access to view and save images. '
          'You can enable this in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = (log(bytes) / log(1024)).floor();
    double size = bytes / pow(1024, i);
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.lightBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.no_photography,
                size: 60,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              Platform.isIOS
                  ? 'Photo Library Access Required'
                  : 'Storage Permission Required',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.darkBlue,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              Platform.isIOS
                  ? 'Please grant access to your photo library to view your photos'
                  : 'Please grant storage permission to view your photos',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grey, fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _checkPermissionAndLoad,
              icon: const Icon(Icons.settings),
              label: const Text('Grant Permission'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: openAppSettings,
              child: const Text('Open App Settings'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Flatten all assets for counting
    int totalAssets = _groupedAssets.values.expand((e) => e).length;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.lightBlue, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header - changes based on selection mode
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // Back button or cancel selection
                    if (_isSelectionMode)
                      IconButton(
                        onPressed: _clearSelection,
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryBlue.withAlpha(51),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.close,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      )
                    else
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryBlue.withAlpha(51),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),

                    const SizedBox(width: 16),

                    // Title
                    if (_isSelectionMode)
                      Text(
                        '${_selectedAssetIds.length} selected',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkBlue,
                        ),
                      )
                    else
                      const Text(
                        'Gallery',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkBlue,
                        ),
                      ),

                    const Spacer(),

                    // Selection mode actions
                    if (_isSelectionMode) ...[
                      // Select all button
                      if (_selectedAssetIds.length < totalAssets)
                        IconButton(
                          onPressed: _selectAll,
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryBlue.withAlpha(51),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.select_all,
                              color: AppColors.primaryBlue,
                              size: 20,
                            ),
                          ),
                        ),

                      // Share selected
                      if (_selectedAssetIds.isNotEmpty)
                        IconButton(
                          onPressed: _shareSelectedImages,
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryBlue.withAlpha(51),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.share,
                              color: AppColors.primaryBlue,
                              size: 20,
                            ),
                          ),
                        ),

                      // Delete selected
                      if (_selectedAssetIds.isNotEmpty)
                        IconButton(
                          onPressed: _deleteSelectedImages,
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.error.withAlpha(51),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.delete_outline,
                              color: _isDeleting
                                  ? AppColors.grey
                                  : AppColors.error,
                              size: 20,
                            ),
                          ),
                        ),
                    ] else
                      // Normal mode actions
                      IconButton(
                        onPressed: _refreshGallery,
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryBlue.withAlpha(51),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.refresh,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Stats
              if (!_isLoading && totalAssets > 0 && !_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withAlpha(26),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$totalAssets ${totalAssets == 1 ? 'photo' : 'photos'} in ${_dateGroups.length} ${_dateGroups.length == 1 ? 'day' : 'days'}',
                          style: const TextStyle(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 10),

              // Image grid with date grouping
              Expanded(
                child: !_hasPermission
                    ? _buildPermissionDenied()
                    : _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: AppColors.primaryBlue,
                            ),
                            SizedBox(height: 20),
                            Text('Loading gallery...'),
                          ],
                        ),
                      )
                    : totalAssets == 0
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _refreshGallery,
                        color: AppColors.primaryBlue,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _dateGroups.length,
                          itemBuilder: (context, groupIndex) {
                            String dateKey = _dateGroups[groupIndex];
                            List<AssetEntity> groupAssets =
                                _groupedAssets[dateKey]!;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Date header
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryBlue,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.primaryBlue
                                                  .withAlpha(77),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.calendar_today,
                                              size: 14,
                                              color: Colors.white.withAlpha(
                                                230,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _formatGroupDate(dateKey),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withAlpha(
                                                  51,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                '${groupAssets.length}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Grid for this date group
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        crossAxisSpacing: 4,
                                        mainAxisSpacing: 4,
                                        childAspectRatio: 1,
                                      ),
                                  itemCount: groupAssets.length,
                                  itemBuilder: (context, localIndex) {
                                    final asset = groupAssets[localIndex];
                                    final globalIndex = _getGlobalIndex(
                                      dateKey,
                                      localIndex,
                                    );
                                    final isSelected = _selectedAssetIds
                                        .contains(asset.id);

                                    return _buildImageTile(
                                      asset,
                                      globalIndex,
                                      dateKey,
                                      localIndex,
                                      isSelected,
                                    );
                                  },
                                ),

                                // Add spacing between groups
                                if (groupIndex < _dateGroups.length - 1)
                                  const SizedBox(height: 16),
                              ],
                            );
                          },
                        ),
                      ),
              ),

              // Loading more indicator
              if (_isLoadingMore)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCamera,
        backgroundColor: AppColors.primaryBlue,
        elevation: 6,
        child: const Icon(Icons.camera_alt, color: Colors.white, size: 28),
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Future<void> _openCamera() async {
    final status = await Permission.camera.request();

    if (status.isGranted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CameraPage()),
      ).then((_) {
        // Refresh gallery when returning
        _refreshGallery();
      });
    } else {
      _showCameraPermissionDialog();
    }
  }

  void _showCameraPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text('Please grant camera permission to take photos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: AppColors.lightBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                size: 70,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No photos yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.darkBlue,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Take photos and they will appear here',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.grey, fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildImageTile(
    AssetEntity asset,
    int globalIndex,
    String dateKey,
    int localIndex,
    bool isSelected,
  ) {
    return GestureDetector(
      onTap: () => _handleImageTap(asset, globalIndex),
      onLongPress: () => _handleImageLongPress(asset.id),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: AppColors.primaryBlue, width: 3)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(26),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image thumbnail
              FutureBuilder<Uint8List?>(
                future: asset.thumbnailDataWithSize(
                  const ThumbnailSize(200, 200),
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData &&
                      snapshot.data != null) {
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildErrorTile();
                      },
                    );
                  }

                  return _buildErrorTile();
                },
              ),

              // Selection overlay
              if (_isSelectionMode)
                Positioned.fill(
                  child: Container(
                    color: isSelected
                        ? AppColors.primaryBlue.withAlpha(77)
                        : Colors.black.withAlpha(102),
                  ),
                ),

              // Selection checkbox
              if (_isSelectionMode)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryBlue
                          : Colors.white.withAlpha(179),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? Colors.white
                            : AppColors.primaryBlue,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ),

              // Position indicator (local index in group) - only in normal mode
              if (!_isSelectionMode)
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(102),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${localIndex + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (50 * globalIndex).ms);
  }

  Widget _buildErrorTile() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Icon(Icons.broken_image, size: 30, color: Colors.grey),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }
}
