import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../../theme/app_theme.dart';
import '../domain/note.dart';
import '../domain/note_content.dart';

/// Full-screen word-processor style editor for personal notes.
///
/// The B / I / U controls are real formatting toggles:
/// - with a selection they format exactly that selection;
/// - with a collapsed cursor they stay active for everything typed next;
/// - each attribute has its own independent on/off state;
/// - formatting is saved as Quill Delta JSON, never as visible symbols.
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({this.note, super.key});

  final Note? note;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _titleController;
  late final quill.QuillController _bodyController;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();
  late bool _isPinned;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleController = TextEditingController(text: note?.title ?? '');
    _isPinned = note?.isPinned ?? false;

    final document = _openDocument(note);
    _bodyController = quill.QuillController(
      document: document,
      selection: TextSelection.collapsed(
        offset: document.length > 0 ? document.length - 1 : 0,
      ),
    );
  }

  quill.Document _openDocument(Note? note) {
    final delta = note?.deltaJson;
    if (delta != null && delta.isNotEmpty) {
      try {
        final decoded = jsonDecode(delta);
        if (decoded is List) return quill.Document.fromJson(decoded);
      } catch (error) {
        debugPrint('Stored rich note could not be opened: $error');
      }
    }
    // Existing plain-text / Markdown notes are converted in memory only.
    // The stored copy is untouched until the user saves.
    return quill.Document.fromJson(legacyMarkdownToDeltaOps(note?.body ?? ''));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  bool _isActive(quill.Attribute<dynamic> attribute) {
    final style = _bodyController.getSelectionStyle();
    return style.attributes.containsKey(attribute.key);
  }

  void _toggle(quill.Attribute<dynamic> attribute) {
    final active = _isActive(attribute);
    _bodyController.formatSelection(
      active ? quill.Attribute.clone(attribute, null) : attribute,
    );
    _editorFocusNode.requestFocus();
  }

  void _save() {
    final plainText = _bodyController.document.toPlainText().trim();
    final title = _titleController.text.trim();
    if (plainText.isEmpty && title.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final deltaJson = jsonEncode(_bodyController.document.toDelta().toJson());
    Navigator.pop(
      context,
      Note(
        id: widget.note?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        body: plainText,
        deltaJson: deltaJson,
        source: widget.note?.source,
        updatedAt: DateTime.now(),
        isPinned: _isPinned,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'New note' : 'Edit note'),
        actions: [
          IconButton(
            tooltip: _isPinned ? 'Unpin note' : 'Pin note',
            onPressed: () => setState(() => _isPinned = !_isPinned),
            icon: Icon(
              _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            ),
          ),
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Save'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Stored privately on this device',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      prefixIcon: Icon(Icons.title_rounded),
                    ),
                  ),
                  if (widget.note?.source != null) ...[
                    const SizedBox(height: 10),
                    _SourceBanner(source: widget.note!.source!),
                  ],
                  const SizedBox(height: 12),
                  _FormatToolbar(
                    controller: _bodyController,
                    isActive: _isActive,
                    onToggle: _toggle,
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.field),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: quill.QuillEditor.basic(
                        controller: _bodyController,
                        focusNode: _editorFocusNode,
                        scrollController: _editorScrollController,
                        config: quill.QuillEditorConfig(
                          scrollable: true,
                          autoFocus: widget.note == null,
                          placeholder: 'Write your note\u2026',
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                          expands: false,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded, size: 19),
                    label: const Text('Save note'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormatToolbar extends StatelessWidget {
  const _FormatToolbar({
    required this.controller,
    required this.isActive,
    required this.onToggle,
  });

  final quill.QuillController controller;
  final bool Function(quill.Attribute<dynamic>) isActive;
  final void Function(quill.Attribute<dynamic>) onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.field),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              'FORMAT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontSize: 9,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Spacer(),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FormatToggleButton(
                  tooltip: 'Bold',
                  icon: Icons.format_bold_rounded,
                  active: isActive(quill.Attribute.bold),
                  onPressed: () => onToggle(quill.Attribute.bold),
                ),
                _FormatToggleButton(
                  tooltip: 'Italic',
                  icon: Icons.format_italic_rounded,
                  active: isActive(quill.Attribute.italic),
                  onPressed: () => onToggle(quill.Attribute.italic),
                ),
                _FormatToggleButton(
                  tooltip: 'Underline',
                  icon: Icons.format_underlined_rounded,
                  active: isActive(quill.Attribute.underline),
                  onPressed: () => onToggle(quill.Attribute.underline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatToggleButton extends StatelessWidget {
  const _FormatToggleButton({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        style: IconButton.styleFrom(
          backgroundColor: active ? colors.secondaryContainer : null,
          foregroundColor: active
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _SourceBanner extends StatelessWidget {
  const _SourceBanner({required this.source});

  final NoteSource source;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadii.field),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_stories_rounded,
            size: 17,
            color: colors.onSecondaryContainer,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              source.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
