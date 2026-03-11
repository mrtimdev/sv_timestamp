class CapturedImage {
  final String id;
  final String imagePath;
  final DateTime timestamp;
  final Map<String, double>? location; // latitude, longitude
  final String? address;
  final Map<String, dynamic> additionalData;
  final bool hasWatermark;
  final String? watermarkTemplate;
  final String? originalPath; // Original image path

  CapturedImage({
    required this.id,
    required this.imagePath,
    required this.timestamp,
    this.location,
    this.address,
    this.additionalData = const {},
    this.hasWatermark = true,
    this.watermarkTemplate,
    this.originalPath,
  });

  // Convert to JSON for storage (used by StorageService)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'timestamp': timestamp.toIso8601String(),
      'location': location,
      'address': address,
      'additionalData': additionalData,
      'hasWatermark': hasWatermark,
      'watermarkTemplate': watermarkTemplate,
      'originalPath': originalPath,
    };
  }

  // Create from JSON (used by StorageService)
  factory CapturedImage.fromJson(Map<String, dynamic> json) {
    return CapturedImage(
      id: json['id'],
      imagePath: json['imagePath'],
      timestamp: DateTime.parse(json['timestamp']),
      location: json['location'] != null
          ? Map<String, double>.from(json['location'])
          : null,
      address: json['address'],
      additionalData: Map<String, dynamic>.from(json['additionalData']),
      hasWatermark: json['hasWatermark'] ?? true,
      watermarkTemplate: json['watermarkTemplate'],
      originalPath: json['originalPath'],
    );
  }

  // Keep toMap for backward compatibility if needed
  Map<String, dynamic> toMap() {
    return toJson();
  }

  // Keep fromMap for backward compatibility if needed
  factory CapturedImage.fromMap(Map<String, dynamic> map) {
    return CapturedImage.fromJson(map);
  }

  // Copy with method for easier updates
  CapturedImage copyWith({
    String? id,
    String? imagePath,
    DateTime? timestamp,
    Map<String, double>? location,
    String? address,
    Map<String, dynamic>? additionalData,
    bool? hasWatermark,
    String? watermarkTemplate,
    String? originalPath,
  }) {
    return CapturedImage(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      timestamp: timestamp ?? this.timestamp,
      location: location ?? this.location,
      address: address ?? this.address,
      additionalData: additionalData ?? this.additionalData,
      hasWatermark: hasWatermark ?? this.hasWatermark,
      watermarkTemplate: watermarkTemplate ?? this.watermarkTemplate,
      originalPath: originalPath ?? this.originalPath,
    );
  }
}
