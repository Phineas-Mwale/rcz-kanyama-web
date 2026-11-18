import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:rcz_kanyama/features/notes/domain/note.dart';
import 'package:rcz_kanyama/features/notes/domain/note_content.dart';

void main() {
  test('legacy notes load and preview without Markdown symbols', () {
    final note = Note.fromJson({
      'id': 'legacy-1',
      'title': 'Prayer',
      'body': '**Bold** and *italic* and __underline__\n# Heading\n- item',
      'updatedAt': '2026-01-02T09:30:00.000',
      'isPinned': false,
    });

    expect(note.isRich, isFalse);
    expect(note.title, 'Prayer');
    expect(note.previewText, 'Bold and italic and underline Heading item');
    expect(note.updatedAt.year, 2026);
  });

  test('rich notes keep Delta JSON and scripture source metadata', () {
    final source = NoteSource(
      type: 'verse',
      translationId: 'ccl',
      translationName: 'Chichewa Contemporary',
      bookId: 'psa',
      bookName: 'Psalms',
      chapter: 23,
      verse: 1,
    );
    final note = Note(
      id: 'n1',
      title: 'Psalm 23:1',
      body: '"The Lord is my shepherd."\nPsalm 23:1 - Chichewa Contemporary',
      deltaJson: jsonEncode(
        buildScriptureDelta(
          verseText: 'The Lord is my shepherd.',
          reference: 'Psalm 23:1',
          translationName: 'Chichewa Contemporary',
          leaveRoomForReflection: true,
        ),
      ),
      source: source,
      updatedAt: DateTime(2026, 2, 3),
      isPinned: true,
    );

    final restored = Note.fromJson(note.toJson());

    expect(restored.isRich, isTrue);
    expect(restored.deltaJson, note.deltaJson);
    expect(restored.isScriptureNote, isTrue);
    expect(restored.source!.reference, 'Psalms 23:1');
    expect(restored.source!.translationName, 'Chichewa Contemporary');
    expect(restored.source!.key, 'ccl|psa|23|1');
    expect(restored.isPinned, isTrue);
    expect(
      restored.matches('shepherd'),
      isTrue,
      reason: 'search must still find scripture text',
    );
  });

  test('verse identity includes translation, book, chapter and verse', () {
    const a = NoteSource(
      type: 'verse',
      translationId: 'ccl',
      translationName: 'Chichewa',
      bookId: 'psa',
      bookName: 'Psalms',
      chapter: 23,
      verse: 1,
    );
    const b = NoteSource(
      type: 'verse',
      translationId: 'web',
      translationName: 'WEB',
      bookId: 'psa',
      bookName: 'Psalms',
      chapter: 23,
      verse: 1,
    );
    const c = NoteSource(
      type: 'verse',
      translationId: 'ccl',
      translationName: 'Chichewa',
      bookId: 'jhn',
      bookName: 'John',
      chapter: 1,
      verse: 1,
    );

    expect(a.key, isNot(b.key));
    expect(a.key, isNot(c.key));
  });

  test('legacy Markdown converts to real formatting instead of symbols', () {
    final ops = legacyMarkdownToDeltaOps(
      '**Bold** *italic* __underline__\n## Heading\n- bullet',
    );

    final plain = ops.map((op) => op['insert']).whereType<String>().join();

    expect(plain, isNot(contains('**')));
    expect(plain, isNot(contains('__')));
    expect(
      ops.any((op) => (op['attributes'] as Map?)?['bold'] == true),
      isTrue,
    );
    expect(
      ops.any((op) => (op['attributes'] as Map?)?['italic'] == true),
      isTrue,
    );
    expect(
      ops.any((op) => (op['attributes'] as Map?)?['underline'] == true),
      isTrue,
    );
    expect(ops.any((op) => (op['attributes'] as Map?)?['header'] == 2), isTrue);
    expect(
      ops.any((op) => (op['attributes'] as Map?)?['list'] == 'bullet'),
      isTrue,
    );
  });

  test('saved Delta JSON reopens with formatting intact and no symbols', () {
    final saved = jsonEncode([
      {
        'insert': 'Bold',
        'attributes': {'bold': true},
      },
      {
        'insert': ' italic',
        'attributes': {'italic': true},
      },
      {
        'insert': ' underline',
        'attributes': {'underline': true},
      },
      {'insert': '\n'},
    ]);

    final document = quill.Document.fromJson(
      jsonDecode(saved) as List<dynamic>,
    );

    expect(document.toPlainText(), 'Bold italic underline\n');
    expect(
      document.toDelta().toJson(),
      jsonDecode(saved),
      reason: 'formatting must survive closing and reopening the note',
    );
  });
}
