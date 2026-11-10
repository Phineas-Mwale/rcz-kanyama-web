import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';

import '../domain/bible_content_store.dart';

/// Persistent cross-platform Bible storage.
/// Android/iOS use a local Sembast database; Flutter Web uses IndexedDB.
class BibleLocalStore implements BibleContentStore {
  BibleLocalStore._(this._database);

  final Database _database;
  static final StoreRef<String, String> _records = StoreRef<String, String>.main();

  static Future<BibleLocalStore> open() async {
    final Database database;
    if (kIsWeb) {
      database = await databaseFactoryWeb.openDatabase('rcz_kanyama_bible_v1');
    } else {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      database = await databaseFactoryIo.openDatabase(
        p.join(directory.path, 'rcz_kanyama_bible_v1.db'),
      );
    }
    return BibleLocalStore._(database);
  }

  String _prefix(String id) {
    _validateId(id);
    return 'translation/$id/';
  }

  void _validateId(String value) {
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, 'id', 'Invalid Bible identifier.');
    }
  }

  String _fileKey(String id, String relativePath) =>
      '${_prefix(id)}file/$relativePath';

  @override
  Future<bool> isTranslationInstalled(String translationId) async {
    return await _records.record('${_prefix(translationId)}installed').get(_database) == '1';
  }

  @override
  Future<List<String>> installedTranslationIds() async {
    final snapshots = await _records.find(_database);
    final result = <String>[];
    for (final snapshot in snapshots) {
      final key = snapshot.key;
      if (key.startsWith('translation/') && key.endsWith('/installed') && snapshot.value == '1') {
        final parts = key.split('/');
        if (parts.length == 3) result.add(parts[1]);
      }
    }
    return result;
  }

  @override
  Future<String> readManifestJson(String translationId) async {
    final value = await _records.record(_fileKey(translationId, 'manifest.json')).get(_database);
    if (value == null) throw StateError('The installed Bible manifest is missing.');
    return value;
  }

  @override
  Future<String> readChapterJson({
    required String translationId,
    required String bookId,
    required int chapter,
  }) async {
    _validateId(bookId);
    if (chapter < 1) throw RangeError.value(chapter, 'chapter');
    final value = await _records
        .record(_fileKey(translationId, 'books/$bookId/$chapter.json'))
        .get(_database);
    if (value == null) throw StateError('This chapter is not available in the installed Bible.');
    return value;
  }

  /// Atomically replaces a translation's records and marks it installed last.
  Future<void> installFiles(String translationId, Map<String, String> files) async {
    final prefix = _prefix(translationId);
    await _database.transaction((transaction) async {
      final existing = await _records.find(transaction);
      for (final record in existing) {
        if (record.key.startsWith(prefix)) {
          await _records.record(record.key).delete(transaction);
        }
      }
      for (final entry in files.entries) {
        await _records.record(_fileKey(translationId, entry.key)).put(transaction, entry.value);
      }
      await _records.record('${prefix}installed').put(transaction, '1');
    });
  }

  Future<void> removeTranslation(String translationId) async {
    final prefix = _prefix(translationId);
    await _database.transaction((transaction) async {
      final existing = await _records.find(transaction);
      for (final record in existing) {
        if (record.key.startsWith(prefix)) {
          await _records.record(record.key).delete(transaction);
        }
      }
    });
  }
}
