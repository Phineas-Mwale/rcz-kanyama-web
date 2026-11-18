import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../notes/data/notes_repository.dart';
import '../../notes/domain/note.dart';
import '../../notes/domain/note_content.dart';
import '../../notes/presentation/note_editor_page.dart';
import '../data/bible_reader_store.dart';
import '../domain/bible_models.dart';

/// Contextual actions for one verse. The sheet is intentionally the only
/// permanent interaction surface: the reading page stays clean.
Future<void> showVerseActionsSheet({
  required BuildContext context,
  required BibleTranslationManifest manifest,
  required BibleBook book,
  required int chapter,
  required BibleVerse verse,
  required VoidCallback onChanged,
}) async {
  final store = BibleReaderStore.instance;
  final notes = NotesRepository.instance;
  await Future.wait<void>([store.ensureLoaded(), notes.ensureLoaded()]);
  if (!context.mounted) return;

  final reference = VerseReference(
    translationId: manifest.id,
    bookId: book.id,
    chapter: chapter,
    verse: verse.number,
  );
  final highlighted = store.isHighlighted(reference);
  final bookmarked = store.isBookmarked(reference);
  final existingNote = notes.findByVerse(
    translationId: manifest.id,
    bookId: book.id,
    chapter: chapter,
    verse: verse.number,
  );

  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final referenceLabel = '${book.name} $chapter:${verse.number}';
  final shareText = '"${verse.text}"\n$referenceLabel \u2014 ${manifest.name}';

  Note buildDraft({required bool leaveRoomForReflection}) => Note(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    title: referenceLabel,
    body: buildScripturePlainText(
      verseText: verse.text,
      reference: referenceLabel,
      translationName: manifest.name,
    ),
    deltaJson: buildScriptureDelta(
      verseText: verse.text,
      reference: referenceLabel,
      translationName: manifest.name,
      leaveRoomForReflection: leaveRoomForReflection,
    ),
    source: NoteSource(
      type: 'verse',
      translationId: manifest.id,
      translationName: manifest.name,
      bookId: book.id,
      bookName: book.name,
      chapter: chapter,
      verse: verse.number,
    ),
    updatedAt: DateTime.now(),
    isPinned: false,
  );

  Future<void> openEditor(Note note) async {
    final result = await navigator.push<Note>(
      MaterialPageRoute<Note>(builder: (_) => NoteEditorPage(note: note)),
    );
    if (result != null) await notes.save(result);
  }

  Future<void> saveScriptureToNotes() async {
    final existing = notes.findByVerse(
      translationId: manifest.id,
      bookId: book.id,
      chapter: chapter,
      verse: verse.number,
    );
    if (existing != null) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('This verse is already saved in Notes.'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => unawaited(openEditor(existing)),
          ),
        ),
      );
      return;
    }
    await notes.save(buildDraft(leaveRoomForReflection: false));
    messenger.showSnackBar(
      const SnackBar(content: Text('Saved to your Notes.')),
    );
  }

  Future<void> addReflection() async {
    final existing = notes.findByVerse(
      translationId: manifest.id,
      bookId: book.id,
      chapter: chapter,
      verse: verse.number,
    );
    await openEditor(existing ?? buildDraft(leaveRoomForReflection: true));
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final colors = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      referenceLabel,
                      style: Theme.of(sheetContext).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      manifest.name,
                      style: Theme.of(sheetContext).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy verse'),
                subtitle: const Text('Verse, reference and translation'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Clipboard.setData(ClipboardData(text: shareText));
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Verse copied.')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded),
                title: const Text('Share verse'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await SharePlus.instance.share(ShareParams(text: shareText));
                },
              ),
              ListTile(
                leading: Icon(
                  highlighted
                      ? Icons.highlight_off_rounded
                      : Icons.highlight_rounded,
                ),
                title: Text(
                  highlighted ? 'Remove highlight' : 'Highlight verse',
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await store.toggleHighlight(reference);
                  onChanged();
                },
              ),
              ListTile(
                leading: Icon(
                  bookmarked
                      ? Icons.bookmark_remove_rounded
                      : Icons.bookmark_add_outlined,
                ),
                title: Text(bookmarked ? 'Remove bookmark' : 'Bookmark verse'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await store.toggleBookmark(
                    BibleBookmark(
                      translationId: manifest.id,
                      translationName: manifest.name,
                      bookId: book.id,
                      bookName: book.name,
                      chapter: chapter,
                      verse: verse.number,
                      text: verse.text,
                      createdAt: DateTime.now(),
                    ),
                  );
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        bookmarked ? 'Bookmark removed.' : 'Verse bookmarked.',
                      ),
                    ),
                  );
                  onChanged();
                },
              ),
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('Save to Notes'),
                subtitle: Text(
                  existingNote == null
                      ? 'Adds this scripture to your main Notes dashboard'
                      : 'Already in Notes',
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await saveScriptureToNotes();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: Text(
                  existingNote == null ? 'Add a reflection' : 'Open verse note',
                ),
                subtitle: Text(
                  existingNote == null
                      ? 'Write your thoughts below the scripture'
                      : 'Continue writing your thoughts',
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await addReflection();
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}
