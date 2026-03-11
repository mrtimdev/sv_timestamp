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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.logoUpdated),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context)!.logoUpdateError}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeCustomLogo() {
    final loc = AppLocalizations.of(context);
    if (loc == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.removeLogoTitle),
        content: Text(loc.removeLogoContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () {
              _updateCustomLogo(null);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(loc.logoRemoved),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: Text(loc.remove, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    if (loc == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.settings),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: _resetToDefaults,
            tooltip: loc.resetDefaults,
          ),
        ],
      ),
      body: ListView(
        children: [
          // App Customization
          SettingItem(
            icon: Icons.image,
            title: loc.customLogo,
            subtitle: _customLogoPath != null
                ? loc.customLogoSet
                : loc.useDefaultLogo,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_customLogoPath != null)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: _removeCustomLogo,
                    tooltip: loc.removeLogo,
                  ),
                IconButton(
                  icon: const Icon(Icons.upload),
                  onPressed: _pickCustomLogo,
                  tooltip: loc.uploadLogo,
                ),
              ],
            ),
          ),

          _buildSectionHeader(loc.language),
          SettingItem(
            icon: Icons.language,
            title: loc.language,
            subtitle:
                context.watch<SettingsProvider>().currentLocale.languageCode ==
                    'en'
                ? 'English'
                : 'ខ្មែរ',
            onTap: () => _showLanguageSheet(context),
          ),

          // Camera Settings
          _buildSectionHeader(loc.cameraSettings),
          SettingItem(
            icon: Icons.volume_up,
            title: loc.captureSound,
            subtitle: loc.captureSoundSubtitle,
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
            title: loc.vibrationFeedback,
            subtitle: loc.vibrationFeedbackSubtitle,
            trailing: Switch(
              value: _vibrationOnCapture,
              onChanged: (value) {
                setState(() => _vibrationOnCapture = value);
                _saveSetting('vibration_on_capture', value);
              },
            ),
          ),
          SettingItem(
            icon: Icons.text_fields,
            title: loc.watermarkSize,
            subtitle: loc.watermarkSizeSubtitle,
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: _watermarkSize,
                min: 20.0,
                max: 100.0,
                divisions: 16,
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

          // Storage Settings
          _buildSectionHeader(loc.storageSettings),
          SettingItem(
            icon: Icons.storage,
            title: loc.storageUsage,
            subtitle: loc.storageUsageSubtitle,
            onTap: () => _showStorageInfo(context),
          ),

          // Actions
          _buildSectionHeader(loc.actions),
          SettingItem(
            icon: Icons.delete,
            title: loc.clearAllPhotos,
            subtitle: loc.clearAllPhotosSubtitle,
            onTap: () => _confirmDeleteAll(context),
          ),
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

  void _resetToDefaults() {
    final loc = AppLocalizations.of(context);
    if (loc == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.resetSettingsTitle),
        content: Text(loc.resetSettingsContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () async {
              await _prefs.clear();
              await _loadSettings();

              // Reset MetadataService
              MetadataService.setAppTitle('SV');
              MetadataService.setCustomLogoPath(null);

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(loc.settingsReset),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text(loc.reset),
          ),
        ],
      ),
    );
  }

  void _showStorageInfo(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    if (loc == null) return;

    final storageService = Provider.of<StorageService>(context, listen: false);
    final size = await storageService.getTotalStorageSize();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.storageInfo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${loc.totalImages}: ${storageService.capturedImages.length}'),
            const SizedBox(height: 8),
            Text('${loc.storageUsed}: ${_formatBytes(size)}'),
            const SizedBox(height: 16),
            Text(
              loc.storageNote,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.ok),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAll(BuildContext context) {
    final loc = AppLocalizations.of(context);
    if (loc == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.deleteAllPhotosTitle),
        content: Text(loc.deleteAllPhotosContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final storageService = Provider.of<StorageService>(
                context,
                listen: false,
              );
              await storageService.deleteAllImages();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(loc.allImagesDeleted),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text(
              loc.deleteAll,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
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
    final loc = AppLocalizations.of(context);
    if (loc == null) return;

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
                loc.language,
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
