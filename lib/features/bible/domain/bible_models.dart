// Translation-neutral models for the RCZ Kanyama Bible reader.
// Keep these models independent of Flutter widgets and storage packages.

class BibleTranslationManifest {
  const BibleTranslationManifest({
    required this.schemaVersion,
    required this.id,
    required this.name,
    required this.shortName,
    required this.languageCode,
    required this.languageName,
    required this.version,
    required this.books,
    this.attribution,
    this.license,
  });

  final int schemaVersion;
  final String id;
  final String name;
  final String shortName;
  final String languageCode;
  final String languageName;
  final String version;
  final String? attribution;
  final String? license;
  final List<BibleBook> books;

  factory BibleTranslationManifest.fromJson(Map<String, dynamic> json) {
    final translation = json['translation'] as Map<String, dynamic>;
    return BibleTranslationManifest(
      schemaVersion: json['schemaVersion'] as int,
      id: translation['id'] as String,
      name: translation['name'] as String,
      shortName: translation['shortName'] as String,
      languageCode: translation['languageCode'] as String,
      languageName: translation['languageName'] as String,
      version: translation['version'] as String,
      attribution: translation['attribution'] as String?,
      license: translation['license'] as String?,
      books: (json['books'] as List<dynamic>)
          .map((item) => BibleBook.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class BibleBook {
  const BibleBook({
    required this.id,
    required this.osisId,
    required this.name,
    required this.englishName,
    required this.testament,
    required this.chapterCount,
  });

  final String id;
  final String osisId;
  final String name;
  final String englishName;
  final String testament;
  final int chapterCount;

  factory BibleBook.fromJson(Map<String, dynamic> json) => BibleBook(
        id: json['id'] as String,
        osisId: json['osisId'] as String,
        name: json['name'] as String,
        englishName: json['englishName'] as String,
        testament: json['testament'] as String,
        chapterCount: json['chapterCount'] as int,
      );
}

class BibleVerse {
  const BibleVerse({required this.number, required this.text});

  final int number;
  final String text;

  factory BibleVerse.fromJson(Map<String, dynamic> json) => BibleVerse(
        number: json['number'] as int,
        text: json['text'] as String,
      );
}

class BibleChapter {
  const BibleChapter({
    required this.bookId,
    required this.chapter,
    required this.verses,
  });

  final String bookId;
  final int chapter;
  final List<BibleVerse> verses;

  factory BibleChapter.fromJson(Map<String, dynamic> json) => BibleChapter(
        bookId: json['bookId'] as String,
        chapter: json['chapter'] as int,
        verses: (json['verses'] as List<dynamic>)
            .map((item) => BibleVerse.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}
