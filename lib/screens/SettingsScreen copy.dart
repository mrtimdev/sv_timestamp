import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sv_timestamp/l10n/app_localizations.dart';
import 'package:sv_timestamp/utils/setting_provider.dart';
import 'package:sv_timestamp/utils/storage_service.dart';
import 'package:sv_timestamp/widgets/setting_item.dart';
import 'package:sv_timestamp/utils/metadata_service.dart';
import 'package:image_picker/image_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SharedPreferences _prefs;

  bool _saveOriginal = true;
  bool _autoLocation = true;
  bool _soundOnCapture = true;
  bool _vibrationOnCapture = true;
  String _imageQuality = 'High';
  String _watermarkPosition = 'Bottom Right';
  String _dateFormat = 'DD/MM/YYYY';
  String _timeFormat = '24-hour';
  double _watermarkOpacity = 0.8;
  double _watermarkSize = 25.0;
  String _appTitle = 'SV';
  String? _customLogoPath;

  final List<String> _qualityOptions = ['Low', 'Medium', 'High', 'Ultra'];
  final List<String> _positionOptions = [
    'Top Left',
    'Top Right',
    'Bottom Left',
    'Bottom Right',
    'Center',
  ];
  final List<String> _dateFormats = [
    'DD/MM/YYYY',
    'MM/DD/YYYY',
    'YYYY-MM-DD',
    'DD Month YYYY',
  ];
  final List<String> _timeFormats = ['24-hour', '12-hour'];

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();

    setState(() {
      _saveOriginal = _prefs.getBool('save_original') ?? true;
      _autoLocation = _prefs.getBool('auto_location') ?? true;
      _soundOnCapture = _prefs.getBool('sound_on_capture') ?? true;
      _vibrationOnCapture = _prefs.getBool('vibration_on_capture') ?? true;
      _imageQuality = _prefs.getString('image_quality') ?? 'High';
      _watermarkPosition =
          _prefs.getString('watermark_position') ?? 'Bottom Right';
      _dateFormat = _prefs.getString('date_format') ?? 'DD/MM/YYYY';
      _timeFormat = _prefs.getString('time_format') ?? '24-hour';
      _watermarkOpacity = _prefs.getDouble('watermark_opacity') ?? 0.8;
      _watermarkSize = _prefs.getDouble('watermark_size') ?? 25.0;
      _appTitle = _prefs.getString('app_title') ?? 'SV';
      _customLogoPath = _prefs.getString('custom_logo_path');
    });
  }

  Future<void> _saveSetting<T>(String key, T value) async {
    if (value is bool) {
      await _prefs.setBool(key, value);
    } else if (value is String) {
      await _prefs.setString(key, value);
    } else if (value is double) {
      await _prefs.setDouble(key, value);
    } else if (value is int) {
      await _prefs.setInt(key, value);
    }
  }

  Future<void> _updateAppTitle(String title) async {
    await _saveSetting('app_title', title);
    MetadataService.setAppTitle(title);
    setState(() {
      _appTitle = title;
    });
  }

  Future<void> _updateCustomLogo(String? path) async {
    if (path == null) {
      await _prefs.remove('custom_logo_path');
      MetadataService.setCustomLogoPath(null);
    } else {
      await _saveSetting('custom_logo_path', path);
      MetadataService.setCustomLogoPath(path);
    }
    setState(() {
      _customLogoPath = path;
    });
  }

  Future<void> _pickCustomLogo() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 90,
      );

      if (image != null) {
        await _updateCustomLogo(image.path);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logo updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting logo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _removeCustomLogo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Custom Logo'),
        content: const Text('Are you sure you want to remove the custom logo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _updateCustomLogo(null);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Logo removed successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: _resetToDefaults,
            tooltip: 'Reset to defaults',
          ),
        ],
      ),
      body: ListView(
        children: [
          // App Customization
          // _buildSectionHeader('App Customization'),
          // SettingItem(
          //   icon: Icons.title,
          //   title: 'App Title',
          //   subtitle: _appTitle,
          //   trailing: IconButton(
          //     icon: const Icon(Icons.edit),
          //     onPressed: () => _showAppTitleDialog(context),
          //   ),
          // ),
          SettingItem(
            icon: Icons.image,
            title: 'Custom Logo',
            subtitle: _customLogoPath != null
                ? 'Custom logo set'
                : 'Use default logo',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_customLogoPath != null)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: _removeCustomLogo,
                    tooltip: 'Remove logo',
                  ),
                IconButton(
                  icon: const Icon(Icons.upload),
                  onPressed: _pickCustomLogo,
                  tooltip: 'Upload logo',
                ),
              ],
            ),
          ),

          _buildSectionHeader(AppLocalizations.of(context)!.language),
          SettingItem(
            icon: Icons.language,
            title: AppLocalizations.of(context)!.language,
            subtitle:
                context.watch<SettingsProvider>().currentLocale.languageCode ==
                    'en'
                ? 'English'
                : 'ខ្មែរ',
            onTap: () => _showLanguageSheet(context),
          ),

          // Camera Settings
          _buildSectionHeader('Camera Settings'),
          SettingItem(
            icon: Icons.volume_up,
            title: 'Capture Sound',
            subtitle: 'Play sound when taking photo',
            trailing: Switch(
              value: _soundOnCapture,
              onChanged: (value) {
                setState(() => _soundOnCapture = value);
                _saveSetting('sound_on_capture', value);
              },
            ),
          ),
          SettingItem(
            icon: Icons.vibration,
            title: 'Vibration Feedback',
            subtitle: 'Vibrate on capture',
            trailing: Switch(
              value: _vibrationOnCapture,
              onChanged: (value) {
                setState(() => _vibrationOnCapture = value);
                _saveSetting('vibration_on_capture', value);
              },
            ),
          ),
          // SettingItem(
          //   icon: Icons.photo_filter,
          //   title: 'Image Quality',
          //   subtitle: 'Higher quality uses more storage',
          //   trailing: DropdownButton<String>(
          //     value: _imageQuality,
          //     onChanged: (value) {
          //       if (value != null) {
          //         setState(() => _imageQuality = value);
          //         _saveSetting('image_quality', value);
          //       }
          //     },
          //     items: _qualityOptions
          //         .map((q) => DropdownMenuItem(value: q, child: Text(q)))
          //         .toList(),
          //   ),
          // ),

          // // Location Settings
          // _buildSectionHeader('Location Settings'),
          // SettingItem(
          //   icon: Icons.location_on,
          //   title: 'Auto Location',
          //   subtitle: 'Automatically add location to photos',
          //   trailing: Switch(
          //     value: _autoLocation,
          //     onChanged: (value) {
          //       setState(() => _autoLocation = value);
          //       _saveSetting('auto_location', value);
          //     },
          //   ),
          // ),

          // Watermark Settings
          // _buildSectionHeader('Watermark Settings'),
          // SettingItem(
          //   icon: Icons.water_damage,
          //   title: 'Watermark Position',
          //   subtitle: 'Position of timestamp watermark',
          //   trailing: DropdownButton<String>(
          //     value: _watermarkPosition,
          //     onChanged: (value) {
          //       if (value != null) {
          //         setState(() => _watermarkPosition = value);
          //         _saveSetting('watermark_position', value);
          //       }
          //     },
          //     items: _positionOptions
          //         .map((p) => DropdownMenuItem(value: p, child: Text(p)))
          //         .toList(),
          //   ),
          // ),
          // SettingItem(
          //   icon: Icons.opacity,
          //   title: 'Watermark Opacity',
          //   subtitle: 'Adjust watermark transparency',
          //   trailing: SizedBox(
          //     width: 150,
          //     child: Slider(
          //       value: _watermarkOpacity,
          //       min: 0.1,
          //       max: 1.0,
          //       divisions: 9,
          //       label: '${(_watermarkOpacity * 100).toInt()}%',
          //       onChanged: (value) {
          //         setState(() => _watermarkOpacity = value);
          //       },
          //       onChangeEnd: (value) {
          //         _saveSetting('watermark_opacity', value);
          //       },
          //     ),
          //   ),
          // ),
          SettingItem(
            icon: Icons.text_fields,
            title: 'Watermark Text Size',
            subtitle: 'Size of watermark text',
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: _watermarkSize,
                min: 20.0,
                max: 100.0,
                // divisions: 6,
                label: '${_watermarkSize.toInt()}px',
                onChanged: (value) {
                  setState(() => _watermarkSize = value);
                },
                onChangeEnd: (value) {
                  _saveSetting('watermark_size', value);
                },
              ),
            ),
          ),
          // SettingItem(
          //   icon: Icons.date_range,
          //   title: 'Date Format',
          //   subtitle: 'How dates are displayed',
          //   trailing: DropdownButton<String>(
          //     value: _dateFormat,
          //     onChanged: (value) {
          //       if (value != null) {
          //         setState(() => _dateFormat = value);
          //         _saveSetting('date_format', value);
          //       }
          //     },
          //     items: _dateFormats
          //         .map((f) => DropdownMenuItem(value: f, child: Text(f)))
          //         .toList(),
          //   ),
          // ),
          // SettingItem(
          //   icon: Icons.access_time,
          //   title: 'Time Format',
          //   subtitle: '12-hour or 24-hour format',
          //   trailing: DropdownButton<String>(
          //     value: _timeFormat,
          //     onChanged: (value) {
          //       if (value != null) {
          //         setState(() => _timeFormat = value);
          //         _saveSetting('time_format', value);
          //       }
          //     },
          //     items: _timeFormats
          //         .map((f) => DropdownMenuItem(value: f, child: Text(f)))
          //         .toList(),
          //   ),
          // ),

          // Storage Settings
          // _buildSectionHeader('Storage Settings'),
          // SettingItem(
          //   icon: Icons.save,
          //   title: 'Save Original',
          //   subtitle: 'Keep original unmarked image',
          //   trailing: Switch(
          //     value: _saveOriginal,
          //     onChanged: (value) {
          //       setState(() => _saveOriginal = value);
          //       _saveSetting('save_original', value);
          //     },
          //   ),
          // ),
          SettingItem(
            icon: Icons.storage,
            title: 'Storage Usage',
            subtitle: 'View and manage storage',
            onTap: () => _showStorageInfo(context),
          ),

          // Actions
          _buildSectionHeader('Actions'),
          SettingItem(
            icon: Icons.delete,
            title: 'Clear All Photos',
            subtitle: 'Permanently delete all captured images',
            onTap: () => _confirmDeleteAll(context),
          ),
          // SettingItem(
          //   icon: Icons.info,
          //   title: 'About App',
          //   subtitle: 'Version 1.0.0 • About developer',
          //   onTap: () => _showAboutDialog(context),
          // ),

          // const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _showAppTitleDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController(
      text: _appTitle,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change App Title'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter app title',
            border: OutlineInputBorder(),
          ),
          maxLength: 30,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                _updateAppTitle(newTitle);
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings?'),
        content: const Text('All settings will be reset to default values.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _prefs.clear();
              await _loadSettings();

              // Reset MetadataService
              MetadataService.setAppTitle('SV');
              MetadataService.setCustomLogoPath(null);

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Settings reset to defaults'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _showStorageInfo(BuildContext context) async {
    final storageService = Provider.of<StorageService>(context, listen: false);
    final size = await storageService.getTotalStorageSize();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Storage Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Images: ${storageService.capturedImages.length}'),
            const SizedBox(height: 8),
            Text('Storage Used: ${_formatBytes(size)}'),
            const SizedBox(height: 16),
            const Text(
              'Note: Images are stored locally on your device.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Photos?'),
        content: const Text(
          'This will permanently delete all captured images. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final storageService = Provider.of<StorageService>(
                context,
                listen: false,
              );
              await storageService.deleteAllImages();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All images deleted'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text(
              'Delete All',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: _appTitle,
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2026 SV TimeStamp. All rights reserved.',
      children: [
        const SizedBox(height: 16),
        const Text(
          'A powerful camera app that automatically adds timestamp and location '
          'to your photos. Perfect for documentation, evidence, and memories.',
        ),
        const SizedBox(height: 12),
        const Text('Features:', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('• Real-time timestamp overlay'),
        const Text('• GPS location embedding'),
        const Text('• Customizable watermark'),
        const Text('• Offline functionality'),
        const SizedBox(height: 12),
        const Text('Developed with ❤️ using Flutter'),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }

  void _showLanguageSheet(BuildContext context) {
    final settingsProvider = context.read<SettingsProvider>();
    final currentLocale = settingsProvider.currentLocale;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context)!.language,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              _languageTile(
                context,
                title: 'English',
                locale: const Locale('en', 'US'),
                selected: currentLocale.languageCode == 'en',
              ),
              _languageTile(
                context,
                title: 'ខ្មែរ',
                locale: const Locale('km', 'KH'),
                selected: currentLocale.languageCode == 'km',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _languageTile(
    BuildContext context, {
    required String title,
    required Locale locale,
    required bool selected,
  }) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: () {
        context.read<SettingsProvider>().changeLocale(locale);
        Navigator.pop(context);
      },
    );
  }
}
