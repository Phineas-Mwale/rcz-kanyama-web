import 'dart:convert';

import 'bible_content_store.dart';
import 'bible_models.dart';

/// One matching verse from an installed, offline Bible translation.
class BibleSearchHit {
  const BibleSearchHit({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.text,
  });

  final BibleBook book;
  final int chapter;
  final int verse;
  final String text;

  String get reference => '${book.name} $chapter:$verse';
}

class _VerseSearchEntry {
  const _VerseSearchEntry({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.text,
  });

  final BibleBook book;
  final int chapter;
  final int verse;
  final String text;
}

/// One reader-facing API for every translation (Chichewa, WEB, KJV, ASV, etc.).
class BibleRepository {
  BibleRepository(this._store);

  final BibleContentStore _store;
  final Map<String, BibleTranslationManifest> _manifestCache = {};
  final Map<String, BibleChapter> _chapterCache = {};
  final Map<String, Future<List<_VerseSearchEntry>>> _searchIndexCaches = {};

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

    final jsonMap = jsonDecode(
      await _store.readChapterJson(
        translationId: translationId,
        bookId: bookId,
        chapter: chapter,
      ),
    ) as Map<String, dynamic>;
    final result = BibleChapter.fromJson(jsonMap);
    if (result.bookId != bookId || result.chapter != chapter) {
      throw FormatException('Bible chapter file does not match its path.');
    }
    _chapterCache[cacheKey] = result;
    return result;
  }

  /// Searches the installed translation entirely on-device.
  ///
  /// The verse index is built once per translation and kept for the session,
  /// so later searches filter in memory instead of re-reading every chapter.
  Future<List<BibleSearchHit>> search({
    required String translationId,
    required String query,
    int limit = 80,
  }) async {
    final needle = query.trim().toLowerCase();
    if (needle.length < 2) return const <BibleSearchHit>[];

    final List<_VerseSearchEntry> entries;
    try {
      entries = await _searchIndex(translationId);
    } catch (_) {
      _searchIndexCaches.remove(translationId);
      rethrow;
    }

    final results = <BibleSearchHit>[];
    for (final entry in entries) {
      if (!entry.text.toLowerCase().contains(needle)) continue;
      results.add(
        BibleSearchHit(
          book: entry.book,
          chapter: entry.chapter,
          verse: entry.verse,
          text: entry.text,
        ),
      );
      if (results.length >= limit) break;
    }
    return results;
  }

  Future<List<_VerseSearchEntry>> _searchIndex(String translationId) {
    final cached = _searchIndexCaches[translationId];
    if (cached != null) return cached;
    final future = _buildSearchIndex(translationId);
    _searchIndexCaches[translationId] = future;
    return future;
  }

  Future<List<_VerseSearchEntry>> _buildSearchIndex(
    String translationId,
  ) async {
    final manifest = await translation(translationId);
    final entries = <_VerseSearchEntry>[];
    for (final book in manifest.books) {
      for (
        var chapterNumber = 1;
        chapterNumber <= book.chapterCount;
        chapterNumber++
      ) {
        final data = await chapter(
          translationId: translationId,
          bookId: book.id,
          chapter: chapterNumber,
        );
        for (final verse in data.verses) {
          entries.add(
            _VerseSearchEntry(
              book: book,
              chapter: chapterNumber,
              verse: verse.number,
              text: verse.text,
            ),
          );
        }
      }
    }
    // The index keeps the verse text; the per-chapter copies are no longer
    // needed and would otherwise double the memory used by a whole Bible.
    _chapterCache.clear();
    return entries;
  }

  void clearCache() {
    _manifestCache.clear();
    _chapterCache.clear();
    _searchIndexCaches.clear();
  }
}
