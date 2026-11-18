import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rcz_kanyama/features/bible/domain/bible_content_store.dart';
import 'package:rcz_kanyama/features/bible/domain/bible_repository.dart';

class _FakeBibleStore implements BibleContentStore {
  int chapterReads = 0;

  final Map<String, Map<String, dynamic>> chapters = {
    't/psa/1': {
      'bookId': 'psa',
      'chapter': 1,
      'verses': [
        {'number': 1, 'text': 'The LORD is my shepherd; I shall not want.'},
        {'number': 2, 'text': 'He makes me lie down in green pastures.'},
      ],
    },
    't/psa/2': {
      'bookId': 'psa',
      'chapter': 2,
      'verses': [
        {
          'number': 1,
          'text': 'The earth is the LORD\u2019s, and its fullness.',
        },
      ],
    },
  };

  @override
  Future<bool> isTranslationInstalled(String translationId) async =>
      translationId == 't';

  @override
  Future<List<String>> installedTranslationIds() async => ['t'];

  @override
  Future<String> readManifestJson(String translationId) async => jsonEncode({
    'schemaVersion': 1,
    'translation': {
      'id': 't',
      'name': 'Test Bible',
      'shortName': 'TST',
      'languageCode': 'en',
      'languageName': 'English',
      'version': '1',
    },
    'books': [
      {
        'id': 'psa',
        'osisId': 'Ps',
        'name': 'Psalms',
        'englishName': 'Psalms',
        'testament': 'old',
        'chapterCount': 2,
      },
    ],
  });

  @override
  Future<String> readChapterJson({
    required String translationId,
    required String bookId,
    required int chapter,
  }) async {
    chapterReads++;
    final value = chapters['$translationId/$bookId/$chapter'];
    if (value == null) throw StateError('missing chapter');
    return jsonEncode(value);
  }
}

void main() {
  test('offline search finds installed verses and reuses its index', () async {
    final store = _FakeBibleStore();
    final repository = BibleRepository(store);

    final lord = await repository.search(translationId: 't', query: 'lord');
    expect(lord.map((hit) => hit.reference), ['Psalms 1:1', 'Psalms 2:1']);
    expect(lord.first.text, contains('shepherd'));

    final readsAfterFirstSearch = store.chapterReads;
    expect(readsAfterFirstSearch, 2);

    final shepherd = await repository.search(
      translationId: 't',
      query: 'SHEPHERD',
    );
    expect(shepherd.single.reference, 'Psalms 1:1');
    expect(
      store.chapterReads,
      readsAfterFirstSearch,
      reason: 'the offline index must be reused for later searches',
    );

    expect(
      await repository.search(translationId: 't', query: 'a'),
      isEmpty,
      reason: 'single letters are not searched',
    );
  });

  test('offline search respects the result limit', () async {
    final repository = BibleRepository(_FakeBibleStore());
    final hits = await repository.search(
      translationId: 't',
      query: 'the',
      limit: 1,
    );
    expect(hits, hasLength(1));
    expect(hits.single.reference, 'Psalms 1:1');
  });
}
