import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../domain/note.dart';
import '../domain/note_content.dart';

class NoteViewPage extends StatefulWidget {
  const NoteViewPage({required this.note, required this.onEdit, super.key});

  final Note note;
  final VoidCallback onEdit;

  @override
  State<NoteViewPage> createState() => _NoteViewPageState();
}

class _NoteViewPageState extends State<NoteViewPage> {
  late final quill.QuillController _controller;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = quill.QuillController(
      document: _openDocument(widget.note),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
  }

  quill.Document _openDocument(Note note) {
    final delta = note.deltaJson;
    if (delta != null && delta.isNotEmpty) {
      try {
        final decoded = jsonDecode(delta);
        if (decoded is List) return quill.Document.fromJson(decoded);
      } catch (error) {
        debugPrint('Stored rich note could not be read: $error');
      }
    }
    // Legacy notes are converted for display so no Markdown markers such as
    // `**`, `#` or `-` are ever shown in the read-only view either.
    return quill.Document.fromJson(legacyMarkdownToDeltaOps(note.body));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final note = widget.note;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My note'),
        actions: [
          IconButton(
            tooltip: 'Edit note',
            onPressed: widget.onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              if (note.source != null) ...[
                _ScriptureSourceCard(source: note.source!),
                const SizedBox(height: 18),
              ],
              Row(
                children: [
                  if (note.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.push_pin_rounded,
                        size: 16,
                        color: colors.secondary,
                      ),
                    ),
                  Text(
                    note.source != null
                        ? 'SCRIPTURE NOTE'
                        : note.isPinned
                        ? 'PINNED NOTE'
                        : 'PERSONAL NOTE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.secondary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                note.title.isEmpty ? 'Untitled note' : note.title,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(height: 1.25),
              ),
              const SizedBox(height: 8),
              Text(
                'Updated ${note.updatedAt.day}/${note.updatedAt.month}/${note.updatedAt.year}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Divider(color: colors.outlineVariant),
              const SizedBox(height: 20),
              quill.QuillEditor.basic(
                controller: _controller,
                scrollController: _scrollController,
                config: quill.QuillEditorConfig(
                  scrollable: false,
                  showCursor: false,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScriptureSourceCard extends StatelessWidget {
  const _ScriptureSourceCard({required this.source});

  final NoteSource source;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.auto_stories_rounded,
              size: 19,
              color: colors.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.reference,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  source.translationName,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
