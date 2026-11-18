import 'package:flutter_test/flutter_test.dart';
import 'package:rcz_kanyama/features/bible/data/bible_reader_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('highlights persist and are isolated by translation, book and chapter', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = BibleReaderStore(preferences: preferences);
    await store.ensureLoaded();

    const psalm = VerseReference(
      translationId: 'ccl',
      bookId: 'psa',
      chapter: 23,
      verse: 1,
    );
    const john = VerseReference(
      translationId: 'ccl',
      bookId: 'jhn',
      chapter: 1,
      verse: 1,
    );
    const otherTranslation = VerseReference(
      translationId: 'web',
      bookId: 'psa',
      chapter: 23,
      verse: 1,
    );
    const otherChapter = VerseReference(
      translationId: 'ccl',
      bookId: 'psa',
      chapter: 24,
      verse: 1,
    );

    await store.toggleHighlight(psalm);
    expect(store.isHighlighted(psalm), isTrue);
    expect(store.isHighlighted(john), isFalse);
    expect(store.isHighlighted(otherTranslation), isFalse);
    expect(store.isHighlighted(otherChapter), isFalse);

    final reloaded = BibleReaderStore(preferences: preferences);
    await reloaded.ensureLoaded();
    expect(reloaded.isHighlighted(psalm), isTrue);

    await reloaded.toggleHighlight(psalm);
    expect(reloaded.isHighlighted(psalm), isFalse);
  });

  test('bookmarks persist, navigate by reference and never duplicate', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = BibleReaderStore(preferences: preferences);
    await store.ensureLoaded();

    final bookmark = BibleBookmark(
      translationId: 'ccl',
      translationName: 'Chichewa Contemporary',
      bookId: 'psa',
      bookName: 'Psalms',
      chapter: 23,
      verse: 1,
      text: 'The Lord is my shepherd.',
      createdAt: DateTime(2026, 4, 1, 12),
    );

    await store.toggleBookmark(bookmark);
    expect(store.bookmarks, hasLength(1));
    await store.toggleBookmark(bookmark);
    expect(store.bookmarks, isEmpty, reason: 'second tap removes it');
    await store.toggleBookmark(bookmark);
    expect(
      store.bookmarks,
      hasLength(1),
      reason: 'bookmarking again must never create duplicates',
    );

    final reloaded = BibleReaderStore(preferences: preferences);
    await reloaded.ensureLoaded();
    expect(reloaded.bookmarks, hasLength(1));
    final saved = reloaded.bookmarkFor(bookmark.referenceKey);
    expect(saved, isNotNull);
    expect(saved!.reference, 'Psalms 23:1');
    expect(saved.translationName, 'Chichewa Contemporary');

    await reloaded.removeBookmark(bookmark.id);
    final empty = BibleReaderStore(preferences: preferences);
    await empty.ensureLoaded();
    expect(empty.bookmarks, isEmpty);
  });

  test('legacy highlight storage is imported without being deleted', () async {
    SharedPreferences.setMockInitialValues({
      BibleReaderStore.legacyHighlightsKey: <String>[
        'ccl|psa|23|1',
        'ccl|jhn|1|1',
      ],
    });
    final preferences = await SharedPreferences.getInstance();
    final store = BibleReaderStore(preferences: preferences);
    await store.ensureLoaded();

    expect(
      store.isHighlighted(
        const VerseReference(
          translationId: 'ccl',
          bookId: 'psa',
          chapter: 23,
          verse: 1,
        ),
      ),
      isTrue,
    );
    expect(
      store.isHighlighted(
        const VerseReference(
          translationId: 'ccl',
          bookId: 'jhn',
          chapter: 1,
          verse: 1,
        ),
      ),
      isTrue,
    );
    expect(
      preferences.getStringList(BibleReaderStore.legacyHighlightsKey),
      isNotNull,
      reason: 'migration must not destroy existing data',
    );
  });
}
