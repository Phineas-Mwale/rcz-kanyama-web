import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../domain/bible_content_store.dart';
import 'bible_catalog_service.dart';
import 'bible_local_store.dart';

class BiblePackageInstallerImpl implements BiblePackageInstaller {
  BiblePackageInstallerImpl({
    required this._catalog,
    required this._store,
  });

  final BibleCatalogService _catalog;
  final BibleLocalStore _store;

  @override
  Future<void> install({
    required String translationId,
    required String packageUrl,
    required String expectedSha256,
    required void Function(double progress) onProgress,
  }) async {
    if (!RegExp(r'^[a-z0-9_-]+/[a-zA-Z0-9._-]+\.zip$').hasMatch(packageUrl)) {
      throw ArgumentError.value(packageUrl, 'packageUrl', 'Invalid package path.');
    }
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedSha256)) {
      throw ArgumentError.value(expectedSha256, 'expectedSha256', 'Invalid SHA-256 checksum.');
    }

    onProgress(.04);
    final bytes = await _catalog.downloadPackage(packageUrl);
    onProgress(.42);
    final actualHash = sha256.convert(bytes).toString();
    if (actualHash.toLowerCase() != expectedSha256.toLowerCase()) {
      throw const FormatException('The Bible download failed its integrity check. Please try again.');
    }

    onProgress(.48);
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.files.length > 2500) {
      throw const FormatException('The Bible package contains too many files.');
    }
    final files = <String, String>{};
    var expandedBytes = 0;
    final fileEntries = archive.files.where((entry) => entry.isFile).toList(growable: false);

    for (var index = 0; index < fileEntries.length; index++) {
      final entry = fileEntries[index];
      final path = _safeRelativePath(entry.name);
      if (path == null) continue;
      final content = entry.content;
      final data = content is List<int> ? content : List<int>.from(content as Iterable);
      expandedBytes += data.length;
      if (expandedBytes > 25 * 1024 * 1024) {
        throw const FormatException('The Bible package is larger than the allowed size.');
      }
      if (path.endsWith('.json') || path.endsWith('.txt')) {
        files[path] = utf8.decode(data, allowMalformed: false);
      }
      onProgress(.48 + (.42 * (index + 1) / fileEntries.length));
    }

    final manifestJson = files['manifest.json'];
    if (manifestJson == null) throw const FormatException('The Bible package has no manifest.json.');
    final decoded = jsonDecode(manifestJson) as Map<String, dynamic>;
    final translation = decoded['translation'] as Map<String, dynamic>?;
    if (decoded['schemaVersion'] != 1 || translation?['id'] != translationId) {
      throw const FormatException('The Bible package manifest is invalid or belongs to another translation.');
    }
    if (!files.keys.any((path) => path.startsWith('books/'))) {
      throw const FormatException('The Bible package contains no chapter files.');
    }

    onProgress(.94);
    await _store.installFiles(translationId, files);
    onProgress(1);
  }

  String? _safeRelativePath(String input) {
    final normalized = input.replaceAll('\\', '/');
    if (normalized.startsWith('/') || normalized.contains(':')) return null;
    final parts = normalized.split('/');
    if (parts.any((part) => part == '..' || part.isEmpty || part == '.')) return null;
    return normalized;
  }

  @override
  Future<void> uninstall(String translationId) => _store.removeTranslation(translationId);
}
