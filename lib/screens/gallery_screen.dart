// lib/screens/gallery_screen.dart

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:svs_timestamp/l10n/app_localizations.dart';
import 'package:svs_timestamp/models/captured_image.dart';
import 'package:svs_timestamp/screens/full_screen_image_viewer.dart';
import 'package:svs_timestamp/utils/storage_service.dart';

class GalleryScreen extends StatefulWidget {
  final int initialTab;
  final bool showBackButton;

  const GalleryScreen({
    super.key,
    this.initialTab = 0,
    this.showBackButton = true,
  });

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _scrollController;
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isGridView = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAll(List<CapturedImage> images, bool isOriginalTab) {
    setState(() {
      final filtered = images.where((img) {
        if (isOriginalTab) {
          return img.originalPath != null &&
              File(img.originalPath!).existsSync();
        }
        return true;
      }).toList();

      if (_selectedIds.length == filtered.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.clear();
        _selectedIds.addAll(filtered.map((e) => e.id));
      }
    });
  }

  Future<void> _deleteSelected(StorageService storage) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text(
          'Delete Photos',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Delete ${_selectedIds.length} photo(s)? This cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final id in _selectedIds) {
        final image = storage.capturedImages.firstWhere((img) => img.id == id);
        await _deleteImage(image);
      }
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photos deleted'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteImage(CapturedImage image) async {
    try {
      final watermarkedFile = File(image.imagePath);
      if (await watermarkedFile.exists()) {
        await watermarkedFile.delete();
      }

      if (image.originalPath != null) {
        final originalFile = File(image.originalPath!);
        if (await originalFile.exists()) {
          await originalFile.delete();
        }
      }

      Provider.of<StorageService>(
        context,
        listen: false,
      ).capturedImages.removeWhere((img) => img.id == image.id);
    } catch (e) {
      print('Error deleting image: $e');
    }
  }

  Future<void> _shareSelected() async {
    if (_selectedIds.isEmpty) return;

    final storage = Provider.of<StorageService>(context, listen: false);
    final paths = <String>[];

    for (final id in _selectedIds) {
      final image = storage.capturedImages.firstWhere((img) => img.id == id);
      final isOriginal = _tabController.index == 1;
      final path = isOriginal ? image.originalPath : image.imagePath;

      if (path != null && await File(path).exists()) {
        paths.add(path);
      }
    }

    if (paths.isNotEmpty) {
      await Share.shareXFiles(
        paths.map((p) => XFile(p)).toList(),
        subject: 'Shared from SVS Timestamp',
      );
    }

    _exitSelectionMode();
  }

  Future<void> _shareSingle(CapturedImage image, bool isOriginal) async {
    final path = isOriginal ? image.originalPath : image.imagePath;
    if (path != null && await File(path).exists()) {
      await Share.shareXFiles([
        XFile(path),
      ], subject: 'Photo from SVS Timestamp');
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(storage),
      body: Column(
        children: [
          // _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildImageGrid(storage.capturedImages, false),
                _buildImageGrid(storage.capturedImages, true),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _isSelectionMode ? _buildSelectionFab() : null,
    );
  }

  PreferredSizeWidget? _buildAppBar(StorageService storage) {
    if (_isSelectionMode) {
      return AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _exitSelectionMode,
        ),
        title: Text(
          '${_selectedIds.length} selected',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all, color: Colors.white),
            onPressed: () =>
                _selectAll(storage.capturedImages, _tabController.index == 1),
            tooltip: 'Select All',
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _shareSelected,
            tooltip: 'Share',
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _deleteSelected(storage),
            tooltip: 'Delete',
          ),
        ],
      );
    }

    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      leading: widget.showBackButton
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      title: const Text('Gallery', style: TextStyle(color: Colors.white)),
      actions: [
        IconButton(
          icon: Icon(
            _isGridView ? Icons.view_list : Icons.grid_view,
            color: Colors.white,
          ),
          onPressed: () => setState(() => _isGridView = !_isGridView),
          tooltip: _isGridView ? 'List View' : 'Grid View',
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          color: const Color(0xFF2C2C2C),
          onSelected: (value) {
            if (value == 'select') {
              setState(() => _isSelectionMode = true);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'select',
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Select Multiple',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImageGrid(List<CapturedImage> images, bool showOriginal) {
    final filtered = images.where((img) {
      if (showOriginal) {
        return img.originalPath != null && File(img.originalPath!).existsSync();
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return _buildEmptyState(showOriginal);
    }

    if (_isGridView) {
      return GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 1,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, index) =>
            _buildGridItem(filtered[index], showOriginal),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      itemBuilder: (context, index) =>
          _buildListItem(filtered[index], showOriginal),
    );
  }

  Widget _buildGridItem(CapturedImage image, bool isOriginal) {
    final isSelected = _selectedIds.contains(image.id);
    final displayPath = isOriginal ? image.originalPath! : image.imagePath;

    return GestureDetector(
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(image.id);
        } else {
          _openFullScreen(image, isOriginal);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          HapticFeedback.mediumImpact();
          setState(() {
            _isSelectionMode = true;
            _selectedIds.add(image.id);
          });
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: '${image.id}_${isOriginal ? 'original' : 'watermarked'}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(
                File(displayPath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey[800],
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
          ),
          if (_isSelectionMode)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? Colors.blue : Colors.black54,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  isSelected ? Icons.check : null,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          if (!_isSelectionMode)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: Text(
                  _formatDate(image.timestamp),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListItem(CapturedImage image, bool isOriginal) {
    final isSelected = _selectedIds.contains(image.id);
    final displayPath = isOriginal ? image.originalPath! : image.imagePath;

    return GestureDetector(
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(image.id);
        } else {
          _openFullScreen(image, isOriginal);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          HapticFeedback.mediumImpact();
          setState(() {
            _isSelectionMode = true;
            _selectedIds.add(image.id);
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: Colors.blue, width: 2) : null,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(12),
              ),
              child: Hero(
                tag: '${image.id}_${isOriginal ? 'original' : 'watermarked'}',
                child: Image.file(
                  File(displayPath),
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 120,
                    height: 120,
                    color: Colors.grey[800],
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(image.timestamp),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(image.timestamp),
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    if (image.address != null && image.address!.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              image.address!,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (_isSelectionMode)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected ? Colors.blue : Colors.grey,
                ),
              ),
            if (!_isSelectionMode)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                color: const Color(0xFF2C2C2C),
                onSelected: (value) {
                  if (value == 'share') {
                    _shareSingle(image, isOriginal);
                  } else if (value == 'delete') {
                    _confirmDeleteSingle(image);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('Share', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isOriginal) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isOriginal ? Icons.image : Icons.water_drop,
            color: Colors.grey[700],
            size: 80,
          ),
          const SizedBox(height: 16),
          Text(
            isOriginal ? 'No original images' : 'No watermarked images',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isOriginal
                ? 'Original images are saved when "Keep Original" is enabled'
                : 'Take some photos to see them here',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionFab() {
    return FloatingActionButton.extended(
      onPressed: _exitSelectionMode,
      backgroundColor: Colors.blue,
      icon: const Icon(Icons.check),
      label: const Text('Done'),
    );
  }

  void _openFullScreen(CapturedImage image, bool showOriginal) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FullScreenImageViewer(image: image, showOriginal: showOriginal),
      ),
    );
  }

  Future<void> _confirmDeleteSingle(CapturedImage image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text(
          'Delete Photo',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this photo?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteImage(image);
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo deleted'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateToCheck = DateTime(date.year, date.month, date.day);

    if (dateToCheck == today) {
      return 'Today';
    } else if (dateToCheck == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// Extension to show gallery as bottom sheet from CameraScreen
extension GalleryScreenBottomSheet on GalleryScreen {
  static void show(BuildContext context, {int initialTab = 0}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: GalleryScreen(initialTab: initialTab, showBackButton: false),
          ),
        ),
      ),
    );
  }
}
