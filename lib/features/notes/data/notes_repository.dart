import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/note.dart';

/// Offline notes store backed by the existing `notes` preference key.
///
/// The JSON shape is additive: old notes keep loading, and new fields are
/// ignored by older builds. Existing entries are never rewritten unless the
/// user saves them from the editor.
class NotesRepository extends ChangeNotifier {
  NotesRepository({SharedPreferences? preferences}) {
    _preferences = preferences;
  }

  static final NotesRepository instance = NotesRepository();

  static const String storageKey = 'notes';

  SharedPreferences? _preferences;
  Future<void>? _loading;
  final List<Note> _notes = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;

  List<Note> get notes => List.unmodifiable(_notes);

  Future<void> ensureLoaded([SharedPreferences? preferences]) {
    if (preferences != null) _preferences = preferences;
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    _preferences ??= await SharedPreferences.getInstance();
    try {
      final raw = _preferences!.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            try {
              if (item is Map) {
                _notes.add(Note.fromJson(Map<String, dynamic>.from(item)));
              }
            } catch (error) {
              // Keep every readable note even if one entry is damaged.
              debugPrint('A saved note could not be read: $error');
            }
          }
        }
      }
    } catch (error) {
      debugPrint('Saved notes could not be decoded: $error');
    }
    _sort();
    _loaded = true;
    _loading = null;
    notifyListeners();
  }

  List<Note> search(String query) =>
      _notes.where((note) => note.matches(query)).toList(growable: false);

  Note? findByVerse({
    required String translationId,
    required String bookId,
    required int chapter,
    required int verse,
  }) {
    for (final note in _notes) {
      final source = note.source;
      if (source != null &&
          source.translationId == translationId &&
          source.bookId == bookId &&
          source.chapter == chapter &&
          source.verse == verse) {
        return note;
      }
    }
    return null;
  }

  Future<void> save(Note note) async {
    await ensureLoaded();
    final index = _notes.indexWhere((item) => item.id == note.id);
    if (index >= 0) {
      _notes[index] = note;
    } else {
      _notes.add(note);
    }
    _sort();
    notifyListeners();
    await _persist();
  }

  Future<void> delete(String noteId) async {
    await ensureLoaded();
    final before = _notes.length;
    _notes.removeWhere((note) => note.id == noteId);
    if (_notes.length == before) return;
    notifyListeners();
    await _persist();
  }

  Future<void> togglePin(String noteId) async {
    await ensureLoaded();
    final index = _notes.indexWhere((note) => note.id == noteId);
    if (index < 0) return;
    final note = _notes[index];
    _notes[index] = Note(
      id: note.id,
      title: note.title,
      body: note.body,
      deltaJson: note.deltaJson,
      source: note.source,
      updatedAt: DateTime.now(),
      isPinned: !note.isPinned,
    );
    _sort();
    notifyListeners();
    await _persist();
  }

  void _sort() {
    _notes.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  Future<void> _persist() async {
    _preferences ??= await SharedPreferences.getInstance();
    await _preferences!.setString(
      storageKey,
      jsonEncode(_notes.map((note) => note.toJson()).toList()),
    );
  }
}
