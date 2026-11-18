import 'package:flutter/foundation.dart' show immutable;

/// Where a note came from. Kept on the note itself so the main Notes
/// dashboard can show scripture context even after the Bible is closed.
@immutable
class NoteSource {
  const NoteSource({
    required this.type,
    required this.translationId,
    required this.translationName,
    required this.bookId,
    required this.bookName,
    required this.chapter,
    required this.verse,
  });

  /// Currently always `verse`. Reserved for future sources.
  final String type;
  final String translationId;
  final String translationName;
  final String bookId;
  final String bookName;
  final int chapter;
  final int verse;

  String get reference => '$bookName $chapter:$verse';

  String get label => '$reference \u2014 $translationName';

  /// Stable identity for one verse in one translation. Never just the
  /// verse number: the same number exists in every book and chapter.
  String get key => '$translationId|$bookId|$chapter|$verse';

  factory NoteSource.fromJson(Map<String, dynamic> json) => NoteSource(
    type: json['type'] as String? ?? 'verse',
    translationId: json['translationId'] as String? ?? '',
    translationName: json['translationName'] as String? ?? '',
    bookId: json['bookId'] as String? ?? '',
    bookName: json['bookName'] as String? ?? '',
    chapter: (json['chapter'] as num?)?.toInt() ?? 0,
    verse: (json['verse'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'translationId': translationId,
    'translationName': translationName,
    'bookId': bookId,
    'bookName': bookName,
    'chapter': chapter,
    'verse': verse,
  };
}

@immutable
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    required this.isPinned,
    this.deltaJson,
    this.source,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    final rawSource = json['source'];
    final rawDelta = json['delta'];
    final rawId = json['id'];
    final id = rawId is String && rawId.trim().isNotEmpty
        ? rawId
        : DateTime.now().microsecondsSinceEpoch.toString();
    return Note(
      id: id,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      deltaJson: rawDelta is String && rawDelta.trim().isNotEmpty
          ? rawDelta
          : null,
      source: rawSource is Map
          ? NoteSource.fromJson(Map<String, dynamic>.from(rawSource))
          : null,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      isPinned: json['isPinned'] as bool? ?? false,
    );
  }

  final String id;
  final String title;

  /// Plain text kept for search, previews and backward compatibility.
  /// For rich notes this is the plain-text extraction of [deltaJson].
  final String body;

  /// Quill Delta JSON. Null for notes written before rich text existed.
  final String? deltaJson;

  /// Bible reference for notes created from the reader.
  final NoteSource? source;

  final DateTime updatedAt;
  final bool isPinned;

  bool get isRich => deltaJson != null && deltaJson!.isNotEmpty;

  bool get isScriptureNote => source != null;

  /// Clean one-line preview. Legacy Markdown markers are stripped here so
  /// the dashboard never shows `**` or `#` to the reader.
  String get previewText {
    var text = body;
    if (!isRich) {
      text = text
          .replaceAll(RegExp(r'^#{1,3}\s+', multiLine: true), '')
          .replaceAll(RegExp(r'^[-\*\u2022]\s+', multiLine: true), '')
          .replaceAllMapped(
            RegExp(r'\*\*(.*?)\*\*'),
            (match) => match.group(1) ?? '',
          )
          .replaceAllMapped(
            RegExp(r'__(.*?)__'),
            (match) => match.group(1) ?? '',
          )
          .replaceAllMapped(
            RegExp(r'\*(.*?)\*'),
            (match) => match.group(1) ?? '',
          );
    }
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return title.toLowerCase().contains(needle) ||
        body.toLowerCase().contains(needle) ||
        (source?.label.toLowerCase().contains(needle) ?? false);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'updatedAt': updatedAt.toIso8601String(),
    'isPinned': isPinned,
    if (deltaJson != null) 'delta': deltaJson,
    if (source != null) 'source': source!.toJson(),
  };
}
