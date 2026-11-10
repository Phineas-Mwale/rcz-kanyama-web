import 'dart:convert';

import 'bible_content_store.dart';
import 'bible_models.dart';

/// One reader-facing API for every translation (Chichewa, WEB, KJV, ASV, etc.).
class BibleRepository {
  BibleRepository(this._store);

  final BibleContentStore _store;
  final Map<String, BibleTranslationManifest> _manifestCache = {};
  final Map<String, BibleChapter> _chapterCache = {};

  Future<BibleTranslationManifest> translation(String translationId) async {
    final cached = _manifestCache[translationId];
    if (cached != null) return cached;
    if (!await _store.isTranslationInstalled(translationId)) {
      throw StateError('Translation "$translationId" is not installed.');
    }
    final jsonMap = jsonDecode(
      await _store.readManifestJson(translationId),
    ) as Map<String, dynamic>;
    final manifest = BibleTranslationManifest.fromJson(jsonMap);
    if (manifest.schemaVersion != 1 || manifest.id != translationId) {
      throw FormatException('Unsupported or mismatched Bible manifest.');
    }
    _manifestCache[translationId] = manifest;
    return manifest;
  }

  Future<BibleChapter> chapter({
    required String translationId,
    required String bookId,
    required int chapter,
  }) async {
    if (chapter < 1) throw RangeError.value(chapter, 'chapter');
    final cacheKey = '$translationId/$bookId/$chapter';
    final cached = _chapterCache[cacheKey];
    if (cached != null) return cached;

    final manifest = await translation(translationId);
    final matches = manifest.books.where((book) => book.id == bookId);
    if (matches.isEmpty) throw ArgumentError('Unknown Bible book: $bookId');
    if (chapter > matches.first.chapterCount) {
      throw RangeError.range(chapter, 1, matches.first.chapterCount, 'chapter');
    }

    final jsonMap = jsonDecode(await _store.readChapterJson(
      translationId: translationId,
      bookId: bookId,
      chapter: chapter,
    )) as Map<String, dynamic>;
    final result = BibleChapter.fromJson(jsonMap);
    if (result.bookId != bookId || result.chapter != chapter) {
      throw FormatException('Bible chapter file does not match its path.');
    }
    _chapterCache[cacheKey] = result;
    return result;
  }

  void clearCache() {
    _manifestCache.clear();
    _chapterCache.clear();
  }
}
