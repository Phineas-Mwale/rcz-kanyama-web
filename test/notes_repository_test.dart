import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rcz_kanyama/features/notes/data/notes_repository.dart';
import 'package:rcz_kanyama/features/notes/domain/note.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('existing notes load and are preserved when new notes are added', () async {
    SharedPreferences.setMockInitialValues({
      'notes': jsonEncode([
        {
          'id': 'legacy-1',
          'title': 'Old note',
          'body': '**Keep me**',
          'updatedAt': '2026-01-01T08:00:00.000',
          'isPinned': false,
        },
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final repository = NotesRepository(preferences: preferences);

    await repository.ensureLoaded();
    expect(repository.notes, hasLength(1));
    expect(repository.notes.first.body, '**Keep me**');

    await repository.save(
      Note(
        id: 'rich-1',
        title: 'New note',
        body: 'Plain body',
        deltaJson: jsonEncode([
          {
            'insert': 'Plain body',
            'attributes': {'bold': true},
          },
          {'insert': '\n'},
        ]),
        updatedAt: DateTime(2026, 3, 1),
        isPinned: false,
      ),
    );

    final reloaded = NotesRepository(preferences: preferences);
    await reloaded.ensureLoaded();

    expect(reloaded.notes, hasLength(2));
    final legacy = reloaded.notes.firstWhere((note) => note.id == 'legacy-1');
    expect(legacy.body, '**Keep me**');
    expect(legacy.isRich, isFalse);
    final rich = reloaded.notes.firstWhere((note) => note.id == 'rich-1');
    expect(rich.isRich, isTrue);
    expect(rich.deltaJson, contains('bold'));
  });

  test('verse notes are found by translation and reference, not just number', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = NotesRepository(preferences: preferences);
    await repository.ensureLoaded();

    const source = NoteSource(
      type: 'verse',
      translationId: 'ccl',
      translationName: 'Chichewa',
      bookId: 'psa',
      bookName: 'Psalms',
      chapter: 23,
      verse: 1,
    );
    await repository.save(
      Note(
        id: 'verse-note',
        title: 'Psalm 23:1',
        body: 'The Lord is my shepherd.',
        deltaJson: jsonEncode([
          {'insert': 'The Lord is my shepherd.\n'},
        ]),
        source: source,
        updatedAt: DateTime(2026, 3, 2),
        isPinned: false,
      ),
    );

    expect(
      repository.findByVerse(
        translationId: 'ccl',
        bookId: 'psa',
        chapter: 23,
        verse: 1,
      )?.id,
      'verse-note',
    );
    expect(
      repository.findByVerse(
        translationId: 'web',
        bookId: 'psa',
        chapter: 23,
        verse: 1,
      ),
      isNull,
    );
    expect(
      repository.findByVerse(
        translationId: 'ccl',
        bookId: 'jhn',
        chapter: 1,
        verse: 1,
      ),
      isNull,
    );
  });

  test('pin state and deletion persist', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = NotesRepository(preferences: preferences);
    await repository.ensureLoaded();
    await repository.save(
      Note(
        id: 'n1',
        title: 'Note',
        body: 'Body',
        updatedAt: DateTime(2026, 3, 3),
        isPinned: false,
      ),
    );

    await repository.togglePin('n1');
    expect(repository.notes.first.isPinned, isTrue);

    final reloaded = NotesRepository(preferences: preferences);
    await reloaded.ensureLoaded();
    expect(reloaded.notes.first.isPinned, isTrue);

    await reloaded.delete('n1');
    final afterDelete = NotesRepository(preferences: preferences);
    await afterDelete.ensureLoaded();
    expect(afterDelete.notes, isEmpty);
  });
}
