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
import '../constants/app_colors.dart';

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
        if (album.name == 'SVS-Watermark-Camera') {
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
      _showImagePreview(allAssets[globalIndex], globalIndex);
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

          // Show preview after a short delay
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _showImagePreview(allAssets[globalIndex], globalIndex);
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

  Future<void> _deleteImage(AssetEntity asset) async {
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
        // Delete using PhotoManager
        final List<String> ids = [asset.id];
        final result = await PhotoManager.editor.deleteWithIds(ids);

        if (result.contains(asset.id)) {
          // Rebuild grouped assets after deletion
          List<AssetEntity> allAssets = _groupedAssets.values
              .expand((e) => e)
              .toList();
          allAssets.remove(asset);
          _groupAssetsByDate(allAssets);

          setState(() {
            _selectedImageIndex = null;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Image deleted successfully'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        } else {
          throw Exception('Failed to delete');
        }
      } catch (e) {
        print('Error deleting: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting image: $e'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isDeleting = false);
        }
      }
    }
  }

  // Fixed share function with proper error handling
  Future<void> _shareImage(AssetEntity asset) async {
    try {
      // Loading indicator
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );

      File? imageFile = await asset.originFile;
      imageFile ??= await asset.file;

      if (imageFile == null) {
        throw Exception("Image file not accessible");
      }

      // Create safe cache copy
      final cacheDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sharePath = '${cacheDir.path}/share_$timestamp.jpg';

      // Read bytes and write to temp file
      final bytes = await imageFile.readAsBytes();
      final shareFile = File(sharePath);
      await shareFile.writeAsBytes(bytes);

      // Close loader
      if (mounted) Navigator.pop(context);

      // Share using XFile
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
    } catch (e) {
      print("Share error: $e");
      if (mounted) {
        // Close loader if it's still showing
        try {
          Navigator.pop(context);
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not share image: ${e.toString()}"),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _saveToGallery(AssetEntity asset) async {
    try {
      final file = await asset.file;
      if (file != null) {
        // For iOS, we can just save the file
        if (Platform.isIOS) {
          await GallerySaver.saveImage(
            file.path,
            albumName: 'SVS-Watermark-Camera',
          );
        } else {
          // For Android, use PhotoManager
          await PhotoManager.editor.saveImage(
            file.readAsBytesSync(),
            filename: path.basename(file.path),
            title: path.basename(file.path),
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Image saved to gallery'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      print('Error saving: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Updated image preview with swipe down to close and better zoom
  void _showImagePreview(AssetEntity asset, int globalIndex) {
    // Pre-load adjacent images for smoother swiping
    _preloadAdjacentImages(globalIndex);

    // Get all assets flattened
    List<AssetEntity> allAssets = _groupedAssets.values
        .expand((e) => e)
        .toList();

    // Create a PageController for the PageView
    PageController pageController = PageController(initialPage: globalIndex);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true, // Enable drag to close
      isDismissible: true, // Make dismissible
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height,
      ),
      builder: (context) => WillPopScope(
        onWillPop: () async => true,
        child: DraggableScrollableSheet(
          initialChildSize: 1.0,
          minChildSize: 0.95, // Allow slight drag before closing
          maxChildSize: 1.0,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              color: Colors.transparent,
              child: Stack(
                children: [
                  // PageView for swipeable images with zoom capability
                  PageView.builder(
                    controller: pageController,
                    itemCount: allAssets.length,
                    onPageChanged: (index) {
                      setState(() {
                        _selectedImageIndex = index;
                      });
                      _preloadAdjacentImages(index);
                    },
                    itemBuilder: (context, index) {
                      final currentAsset = allAssets[index];
                      return FutureBuilder<File?>(
                        future: currentAsset.file,
                        builder: (context, snapshot) {
                          final file = snapshot.data;

                          if (snapshot.connectionState !=
                                  ConnectionState.done ||
                              file == null) {
                            return _buildLoadingPlaceholder();
                          }

                          return _buildZoomableImage(
                            file,
                            currentAsset,
                            index,
                            allAssets.length,
                          );
                        },
                      );
                    },
                  ),

                  // Top gradient bar (semi-transparent) - draggable area for swipe down
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      onVerticalDragEnd: (details) {
                        if (details.primaryVelocity! > 500) {
                          Navigator.pop(context);
                        }
                      },
                      child: Container(
                        height: 100,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withAlpha(179),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Empty space for balance (no close button)
                                const SizedBox(width: 40),

                                // Date and time badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(153),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: Colors.white.withAlpha(51),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        color: AppColors.primaryBlue,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _formatDateDetailed(
                                          asset.createDateTime,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Counter badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryBlue,
                                    borderRadius: BorderRadius.circular(30),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primaryBlue.withAlpha(
                                          102,
                                        ),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '${globalIndex + 1}/${allAssets.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
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
                  ),

                  // Bottom gradient bar (semi-transparent)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withAlpha(179),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Bottom action buttons
                  Positioned(
                    bottom: MediaQuery.of(context).padding.bottom + 20,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionButton(
                            icon: Icons.share,
                            label: 'Share',
                            color: Colors.white,
                            backgroundColor: Colors.white.withAlpha(51),
                            onTap: () {
                              Navigator.pop(context);
                              _shareImage(
                                allAssets[pageController.page?.round() ??
                                    globalIndex],
                              );
                            },
                          ),

                          _buildActionButton(
                            icon: Icons.download,
                            label: 'Save',
                            color: Colors.white,
                            backgroundColor: AppColors.primaryBlue,
                            onTap: () {
                              Navigator.pop(context);
                              _saveToGallery(
                                allAssets[pageController.page?.round() ??
                                    globalIndex],
                              );
                            },
                            hasGlow: true,
                          ),

                          _buildActionButton(
                            icon: Icons.delete_outline,
                            label: 'Delete',
                            color: Colors.white,
                            backgroundColor: Colors.red.withAlpha(179),
                            onTap: () {
                              Navigator.pop(context);
                              _deleteImage(
                                allAssets[pageController.page?.round() ??
                                    globalIndex],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Swipe down indicator (small handle)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 0,
                    right: 0,
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
                ],
              ),
            );
          },
        ),
      ),
    ).then((_) {
      // Reset selected index when closing
      setState(() {
        // Keep selection but maybe clear highlight
      });
    });
  }

  // New zoomable image widget
  Widget _buildZoomableImage(
    File file,
    AssetEntity asset,
    int index,
    int totalCount,
  ) {
    return Container(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Zoomable image
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              panEnabled: true,
              scaleEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              clipBehavior: Clip.none,
              child: Hero(
                tag: 'image_${asset.id}',
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildErrorPlaceholder();
                  },
                ),
              ),
            ),
          ),

          // Image info overlay at bottom (semi-transparent)
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(102),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withAlpha(51),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Image metadata
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.photo_camera,
                                size: 14,
                                color: AppColors.primaryBlue,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Image ${index + 1} of $totalCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (asset.title != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              asset.title!,
                              style: TextStyle(
                                color: Colors.white.withAlpha(179),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Image size indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(26),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: FutureBuilder<File?>(
                        future: asset.file,
                        builder: (context, snapshot) {
                          final size = snapshot.data?.lengthSync();
                          return Text(
                            _formatFileSize(size ?? 0),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
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
    required Color color,
    required Color backgroundColor,
    required VoidCallback onTap,
    bool hasGlow = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withAlpha(51), width: 1),
          boxShadow: hasGlow
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
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingPlaceholder() {
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
            style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
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
            child: const Icon(Icons.broken_image, size: 40, color: Colors.red),
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load image',
            style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 14),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = (log(bytes) / log(1024)).floor();
    double size = bytes / pow(1024, i);
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  void _preloadAdjacentImages(int currentIndex) {
    List<AssetEntity> allAssets = _groupedAssets.values
        .expand((e) => e)
        .toList();

    // Preload next and previous images for smoother swiping
    if (currentIndex > 0) {
      allAssets[currentIndex - 1].file;
    }
    if (currentIndex < allAssets.length - 1) {
      allAssets[currentIndex + 1].file;
    }
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

  String _formatDateDetailed(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
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
                    const Text(
                      'Gallery',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkBlue,
                      ),
                    ),
                    const Spacer(),
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
              if (!_isLoading && totalAssets > 0)
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
                                    return _buildImageTile(
                                      asset,
                                      globalIndex,
                                      dateKey,
                                      localIndex,
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
  ) {
    final bool isSelected = _selectedImageIndex == globalIndex;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedImageIndex = globalIndex;
        });
        _showImagePreview(asset, globalIndex);
      },
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

              // Selection indicator
              if (isSelected)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),

              // Index overlay (for debugging/selection)
              if (isSelected)
                Positioned.fill(
                  child: Container(color: AppColors.primaryBlue.withAlpha(26)),
                ),

              // Position indicator (local index in group)
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

// Add warning color to AppColors
// In your AppColors class, add:
// static const Color warning = Color(0xFFFFA000);
