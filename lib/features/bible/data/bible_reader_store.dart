import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identifies one verse inside one downloaded translation.
///
/// The translation and book are part of the key: verse 1 in Psalm 23 must
/// never collide with verse 1 in John 1 or with another translation.
@immutable
class VerseReference {
  const VerseReference({
    required this.translationId,
    required this.bookId,
    required this.chapter,
    required this.verse,
  });

  final String translationId;
  final String bookId;
  final int chapter;
  final int verse;

  String get key => '$translationId|$bookId|$chapter|$verse';
}

@immutable
class BibleBookmark {
  const BibleBookmark({
    required this.translationId,
    required this.translationName,
    required this.bookId,
    required this.bookName,
    required this.chapter,
    required this.verse,
    required this.text,
    required this.createdAt,
  });

  final String translationId;
  final String translationName;
  final String bookId;
  final String bookName;
  final int chapter;
  final int verse;
  final String text;
  final DateTime createdAt;

  String get id => '$translationId|$bookId|$chapter|$verse';

  String get reference => '$bookName $chapter:$verse';

  VerseReference get referenceKey => VerseReference(
    translationId: translationId,
    bookId: bookId,
    chapter: chapter,
    verse: verse,
  );

  factory BibleBookmark.fromJson(Map<String, dynamic> json) => BibleBookmark(
    translationId: json['translationId'] as String? ?? '',
    translationName: json['translationName'] as String? ?? '',
    bookId: json['bookId'] as String? ?? '',
    bookName: json['bookName'] as String? ?? '',
    chapter: (json['chapter'] as num?)?.toInt() ?? 0,
    verse: (json['verse'] as num?)?.toInt() ?? 0,
    text: json['text'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'translationId': translationId,
    'translationName': translationName,
    'bookId': bookId,
    'bookName': bookName,
    'chapter': chapter,
    'verse': verse,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// Offline, translation-aware highlights and bookmarks for the Bible reader.
///
/// Uses SharedPreferences so both Android and Flutter Web work without any
/// backend or new Supabase table.
class BibleReaderStore extends ChangeNotifier {
  BibleReaderStore({SharedPreferences? preferences}) {
    _preferences = preferences;
  }

  static final BibleReaderStore instance = BibleReaderStore();

  static const String highlightsKey = 'bible_verse_highlights_v2';
  static const String bookmarksKey = 'bible_verse_bookmarks_v1';

  /// Previously used by an early reading build. Imported once, never deleted.
  static const String legacyHighlightsKey = 'bible_highlights';

  SharedPreferences? _preferences;
  Future<void>? _loading;
  bool _loaded = false;

  final Set<String> _highlightKeys = <String>{};
  final List<BibleBookmark> _bookmarks = <BibleBookmark>[];

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    _preferences ??= await SharedPreferences.getInstance();

    final rawHighlights = _preferences!.getString(highlightsKey);
    if (rawHighlights != null && rawHighlights.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHighlights);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is String && item.isNotEmpty) _highlightKeys.add(item);
          }
        }
      } catch (error) {
        debugPrint('Saved verse highlights could not be read: $error');
      }
    }

    // Import the old string-list format without removing the old value.
    try {
      final legacy = _preferences!.getStringList(legacyHighlightsKey);
      if (legacy != null) {
        var changed = false;
        for (final key in legacy) {
          if (key.isNotEmpty && _highlightKeys.add(key)) changed = true;
        }
        if (changed) {
          await _persistHighlights();
        }
      }
    } catch (_) {
      // A different type stored under the old key is simply ignored.
    }

    final rawBookmarks = _preferences!.getString(bookmarksKey);
    if (rawBookmarks != null && rawBookmarks.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBookmarks);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              try {
                _bookmarks.add(
                  BibleBookmark.fromJson(Map<String, dynamic>.from(item)),
                );
              } catch (error) {
                debugPrint('A saved verse bookmark could not be read: $error');
              }
            }
          }
        }
      } catch (error) {
        debugPrint('Saved verse bookmarks could not be read: $error');
      }
    }

    _sortBookmarks();
    _loaded = true;
    _loading = null;
    notifyListeners();
  }

  bool isHighlighted(VerseReference reference) =>
      _highlightKeys.contains(reference.key);

  List<BibleBookmark> get bookmarks => List.unmodifiable(_bookmarks);

  bool isBookmarked(VerseReference reference) =>
      _bookmarks.any((bookmark) => bookmark.id == reference.key);

  BibleBookmark? bookmarkFor(VerseReference reference) {
    for (final bookmark in _bookmarks) {
      if (bookmark.id == reference.key) return bookmark;
    }
    return null;
  }

  Future<void> toggleHighlight(VerseReference reference) async {
    await ensureLoaded();
    if (!_highlightKeys.remove(reference.key)) {
      _highlightKeys.add(reference.key);
    }
    notifyListeners();
    await _persistHighlights();
  }

  Future<void> toggleBookmark(BibleBookmark bookmark) async {
    await ensureLoaded();
    final index = _bookmarks.indexWhere((item) => item.id == bookmark.id);
    if (index >= 0) {
      _bookmarks.removeAt(index);
    } else {
      _bookmarks.add(bookmark);
      _sortBookmarks();
    }
    notifyListeners();
    await _persistBookmarks();
  }

  Future<void> removeBookmark(String id) async {
    await ensureLoaded();
    final before = _bookmarks.length;
    _bookmarks.removeWhere((bookmark) => bookmark.id == id);
    if (_bookmarks.length == before) return;
    notifyListeners();
    await _persistBookmarks();
  }

  void _sortBookmarks() {
    _bookmarks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _persistHighlights() async {
    _preferences ??= await SharedPreferences.getInstance();
    final values = _highlightKeys.toList()..sort();
    await _preferences!.setString(highlightsKey, jsonEncode(values));
  }

  Future<void> _persistBookmarks() async {
    _preferences ??= await SharedPreferences.getInstance();
    await _preferences!.setString(
      bookmarksKey,
      jsonEncode(_bookmarks.map((bookmark) => bookmark.toJson()).toList()),
    );
  }
}
