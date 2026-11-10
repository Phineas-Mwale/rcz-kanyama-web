import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class BibleCatalogTranslation {
  const BibleCatalogTranslation({
    required this.id,
    required this.name,
    required this.shortName,
    required this.languageCode,
    required this.status,
    this.version,
    this.packagePath,
    this.sha256,
    this.packageBytes,
    this.licenseLabel,
  });

  final String id;
  final String name;
  final String shortName;
  final String languageCode;
  final String status;
  final String? version;
  final String? packagePath;
  final String? sha256;
  final int? packageBytes;
  final String? licenseLabel;

  bool get isAvailable => status == 'available' && packagePath != null && sha256 != null;

  factory BibleCatalogTranslation.fromJson(Map<String, dynamic> json) => BibleCatalogTranslation(
        id: json['id'] as String,
        name: json['name'] as String,
        shortName: json['shortName'] as String,
        languageCode: json['languageCode'] as String,
        status: json['status'] as String,
        version: json['version'] as String?,
        packagePath: json['packagePath'] as String?,
        sha256: json['sha256'] as String?,
        packageBytes: json['packageBytes'] as int?,
        licenseLabel: json['licenseLabel'] as String?,
      );
}

class BibleCatalogService {
  BibleCatalogService(this._client, {this.bucket = 'bibles'});
  final SupabaseClient _client;
  final String bucket;

  Future<List<BibleCatalogTranslation>> fetchCatalog() async {
    final bytes = await _client.storage.from(bucket).download('catalog.json');
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (decoded['catalogSchemaVersion'] != 1) throw const FormatException('Unsupported Bible catalogue version.');
    final items = decoded['translations'] as List<dynamic>;
    return items.map((item) => BibleCatalogTranslation.fromJson(item as Map<String, dynamic>)).toList(growable: false);
  }

  Future<Uint8List> downloadPackage(String packagePath) => _client.storage.from(bucket).download(packagePath);
}
