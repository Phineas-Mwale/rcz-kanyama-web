/// Categories displayed in the Kanyama Congregation History editor.
///
/// The database stores stable lowercase category keys. Keep the human-readable
/// labels in the app and translate at the repository boundary.
const congregationHistoryCategories = <String>[
  'Pastors',
  'Executives',
  'Secretariat',
  'Milestones',
  'Events',
  'Records',
];

/// Converts an app-facing category label to the value accepted by Supabase.
String historyCategoryToDatabaseValue(String category) {
  switch (category.trim().toLowerCase()) {
    case 'pastors':
      return 'pastors';
    case 'executives':
    case 'congregation_executives':
      return 'congregation_executives';
    case 'secretariat':
      return 'secretariat';
    case 'milestones':
      return 'milestones';
    case 'events':
      return 'events';
    case 'records':
    case 'other':
      return 'other';
    default:
      throw ArgumentError.value(category, 'category', 'Unknown history category');
  }
}

/// Converts the database category key to the label used throughout the app.
String historyCategoryFromDatabaseValue(String category) {
  switch (category.trim().toLowerCase()) {
    case 'pastors':
      return 'Pastors';
    case 'congregation_executives':
    case 'executives':
      return 'Executives';
    case 'secretariat':
      return 'Secretariat';
    case 'milestones':
      return 'Milestones';
    case 'events':
      return 'Events';
    case 'other':
    case 'records':
      return 'Records';
    default:
      return 'Records';
  }
}

String historyCategoryIconName(String category) {
  switch (category.toLowerCase()) {
    case 'pastors':
      return 'pastor';
    case 'executives':
      return 'executive';
    case 'secretariat':
      return 'secretariat';
    case 'milestones':
      return 'milestone';
    case 'events':
      return 'event';
    default:
      return 'record';
  }
}

class CongregationHistoryPhoto {
  const CongregationHistoryPhoto({
    required this.id,
    required this.entryId,
    required this.storagePath,
    required this.displayOrder,
    this.caption,
    this.url,
  });

  final String id;
  final String entryId;
  final String storagePath;
  final String? caption;
  final int displayOrder;
  final String? url;

  CongregationHistoryPhoto copyWith({
    String? caption,
    int? displayOrder,
    String? url,
  }) {
    return CongregationHistoryPhoto(
      id: id,
      entryId: entryId,
      storagePath: storagePath,
      caption: caption ?? this.caption,
      displayOrder: displayOrder ?? this.displayOrder,
      url: url ?? this.url,
    );
  }

  factory CongregationHistoryPhoto.fromJson(Map<String, dynamic> json) {
    return CongregationHistoryPhoto(
      id: json['id']?.toString() ?? '',
      entryId: json['entry_id']?.toString() ?? '',
      storagePath: json['storage_path']?.toString() ?? '',
      caption: json['caption']?.toString(),
      displayOrder: _asInt(json['display_order']) ?? 0,
    );
  }
}

class CongregationHistoryEntry {
  const CongregationHistoryEntry({
    required this.id,
    required this.title,
    required this.category,
    required this.displayOrder,
    required this.isPublished,
    required this.photos,
    this.personName,
    this.position,
    this.startYear,
    this.endYear,
    this.biography,
    this.coverPhotoPath,
    this.coverUrl,
    this.publishedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String category;
  final String? personName;
  final String? position;
  final int? startYear;
  final int? endYear;
  final String? biography;
  final String? coverPhotoPath;
  final String? coverUrl;
  final int displayOrder;
  final bool isPublished;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<CongregationHistoryPhoto> photos;

  String? get yearsLabel {
    final start = startYear;
    final end = endYear;
    if (start == null && end == null) return null;
    if (start != null && end != null) {
      return start == end ? '$start' : '$start – $end';
    }
    if (start != null) return 'From $start';
    return 'Until $end';
  }

  String get peopleLine {
    final name = personName?.trim();
    final role = position?.trim();
    if (name != null && name.isNotEmpty && role != null && role.isNotEmpty) {
      return '$name • $role';
    }
    if (name != null && name.isNotEmpty) return name;
    if (role != null && role.isNotEmpty) return role;
    return '';
  }

  List<String> get allPhotoPaths => [
    if (coverPhotoPath != null && coverPhotoPath!.isNotEmpty) coverPhotoPath!,
    for (final photo in photos)
      if (photo.storagePath.isNotEmpty) photo.storagePath,
  ];

  CongregationHistoryEntry withMedia(Map<String, String> urls) {
    return CongregationHistoryEntry(
      id: id,
      title: title,
      category: category,
      personName: personName,
      position: position,
      startYear: startYear,
      endYear: endYear,
      biography: biography,
      coverPhotoPath: coverPhotoPath,
      coverUrl: coverPhotoPath == null ? null : urls[coverPhotoPath],
      displayOrder: displayOrder,
      isPublished: isPublished,
      publishedAt: publishedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      photos: photos
          .map((photo) => photo.copyWith(url: urls[photo.storagePath]))
          .toList(growable: false),
    );
  }

  factory CongregationHistoryEntry.fromJson(
    Map<String, dynamic> json, {
    List<CongregationHistoryPhoto> photos = const [],
  }) {
    return CongregationHistoryEntry(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      category: historyCategoryFromDatabaseValue(json['category']?.toString() ?? 'other'),
      personName: json['person_name']?.toString(),
      position: json['position']?.toString(),
      startYear: _asInt(json['start_year']),
      endYear: _asInt(json['end_year']),
      biography: json['biography']?.toString(),
      coverPhotoPath: json['cover_photo_path']?.toString(),
      displayOrder: _asInt(json['display_order']) ?? 0,
      isPublished: json['is_published'] == true,
      publishedAt: _asDate(json['published_at']),
      createdAt: _asDate(json['created_at']),
      updatedAt: _asDate(json['updated_at']),
      photos: photos,
    );
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

DateTime? _asDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}
