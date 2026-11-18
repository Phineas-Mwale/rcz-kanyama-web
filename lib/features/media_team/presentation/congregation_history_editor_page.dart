import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../theme/app_theme.dart';
import '../../congregation_history/data/congregation_history_repository.dart';
import '../../congregation_history/domain/congregation_history_models.dart';
import '../../congregation_history/presentation/history_visuals.dart';

class CongregationHistoryEditorPage extends StatefulWidget {
  const CongregationHistoryEditorPage({
    required this.repository,
    this.entry,
    this.suggestedOrder = 0,
    super.key,
  });

  final CongregationHistoryRepository repository;
  final CongregationHistoryEntry? entry;
  final int suggestedOrder;

  @override
  State<CongregationHistoryEditorPage> createState() =>
      _CongregationHistoryEditorPageState();
}

class _CongregationHistoryEditorPageState
    extends State<CongregationHistoryEditorPage> {
  final _title = TextEditingController();
  final _person = TextEditingController();
  final _position = TextEditingController();
  final _startYear = TextEditingController();
  final _endYear = TextEditingController();
  final _biography = TextEditingController();
  final _order = TextEditingController();

  late String _category;
  late bool _published;
  final List<_ExistingPhotoEditor> _existingPhotos = [];
  final List<_NewPhotoEditor> _newPhotos = [];
  final List<String> _deletedPhotoIds = [];
  final List<String> _deletedPhotoPaths = [];

  String? _existingCoverPath;
  String? _existingCoverUrl;
  Uint8List? _newCoverBytes;
  String? _newCoverName;
  String? _newCoverContentType;
  bool _coverRemoved = false;

  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _title.text = entry?.title ?? '';
    _person.text = entry?.personName ?? '';
    _position.text = entry?.position ?? '';
    _startYear.text = entry?.startYear?.toString() ?? '';
    _endYear.text = entry?.endYear?.toString() ?? '';
    _biography.text = entry?.biography ?? '';
    _order.text = (entry?.displayOrder ?? widget.suggestedOrder).toString();
    _category = entry?.category ?? congregationHistoryCategories.first;
    _published = entry?.isPublished ?? false;
    _existingCoverPath = entry?.coverPhotoPath;
    _existingCoverUrl = entry?.coverUrl;
    for (final photo in entry?.photos ?? const <CongregationHistoryPhoto>[]) {
      _existingPhotos.add(_ExistingPhotoEditor(photo));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _person.dispose();
    _position.dispose();
    _startYear.dispose();
    _endYear.dispose();
    _biography.dispose();
    _order.dispose();
    for (final photo in _existingPhotos) {
      photo.caption.dispose();
    }
    for (final photo in _newPhotos) {
      photo.caption.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (_dirty) return;
    // Rebuild so PopScope notices that unsaved changes now exist.
    setState(() => _dirty = true);
  }

  Future<void> _pickCover() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 88,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!_validSize(bytes)) return;
      if (!mounted) return;
      setState(() {
        _newCoverBytes = bytes;
        _newCoverName = file.name;
        _newCoverContentType = _contentType(file.name);
        _coverRemoved = false;
        _markDirty();
      });
    } catch (error) {
      debugPrint('Cover photograph selection failed: $error');
      _message('The photograph could not be selected. Please try another.');
    }
  }

  Future<void> _addPhotos() async {
    try {
      final files = await ImagePicker().pickMultiImage(
        maxWidth: 2400,
        imageQuality: 85,
      );
      if (files.isEmpty) return;
      final added = <_NewPhotoEditor>[];
      for (final file in files) {
        if (_existingPhotos.length + _newPhotos.length + added.length >= 20) {
          _message('A record can hold up to 20 gallery photographs.');
          break;
        }
        final bytes = await file.readAsBytes();
        if (!_validSize(bytes)) continue;
        added.add(
          _NewPhotoEditor(
            bytes: bytes,
            name: file.name,
            contentType: _contentType(file.name),
          ),
        );
      }
      if (!mounted || added.isEmpty) return;
      setState(() {
        _newPhotos.addAll(added);
        _markDirty();
      });
    } catch (error) {
      debugPrint('Gallery photograph selection failed: $error');
      _message('The photographs could not be selected. Please try again.');
    }
  }

  bool _validSize(Uint8List bytes) {
    if (bytes.length > 12 * 1024 * 1024) {
      _message('Each photograph must be smaller than 12 MB.');
      return false;
    }
    return true;
  }

  String _contentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  String _extension(String? name) {
    final lower = (name ?? '').toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.gif')) return 'gif';
    return 'jpg';
  }

  void _removeExistingPhoto(_ExistingPhotoEditor photo) {
    setState(() {
      _existingPhotos.remove(photo);
      _deletedPhotoIds.add(photo.id);
      _deletedPhotoPaths.add(photo.path);
      photo.caption.dispose();
      _markDirty();
    });
  }

  void _moveExistingPhoto(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _existingPhotos.length) return;
    setState(() {
      final photo = _existingPhotos.removeAt(index);
      _existingPhotos.insert(target, photo);
      _markDirty();
    });
  }

  void _moveNewPhoto(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _newPhotos.length) return;
    setState(() {
      final photo = _newPhotos.removeAt(index);
      _newPhotos.insert(target, photo);
      _markDirty();
    });
  }

  Future<void> _save({required bool publish}) async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      _message('Add a title for this record.');
      return;
    }
    final start = _yearValue(_startYear.text);
    final end = _yearValue(_endYear.text);
    if (_startYear.text.trim().isNotEmpty && start == null) {
      _message('Enter a valid start year, for example 1998.');
      return;
    }
    if (_endYear.text.trim().isNotEmpty && end == null) {
      _message('Enter a valid end year, for example 2005.');
      return;
    }
    if (start != null && end != null && start > end) {
      _message('The end year cannot be earlier than the start year.');
      return;
    }
    final orderText = _order.text.trim();
    final order = int.tryParse(orderText);
    if (orderText.isNotEmpty && (order == null || order < 0)) {
      _message('Enter a whole number of zero or more for the display order.');
      return;
    }
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      _message('Your Media Team session has expired. Sign in again.');
      return;
    }

    setState(() => _saving = true);
    final entryId = widget.entry?.id ?? const Uuid().v4();
    final uploadedPaths = <String>[];
    final uploadedNewPhotos = <String, String>{};
    String? coverPath = _coverRemoved ? null : _existingCoverPath;
    var entryInserted = false;
    var entrySaved = false;

    try {
      if (_newCoverBytes != null) {
        final path =
            '${user.id}/$entryId/cover-${DateTime.now().millisecondsSinceEpoch}.${_extension(_newCoverName)}';
        await widget.repository.uploadPhoto(
          path: path,
          bytes: _newCoverBytes!,
          contentType: _newCoverContentType ?? 'image/jpeg',
        );
        uploadedPaths.add(path);
        coverPath = path;
      }

      final stamp = DateTime.now().millisecondsSinceEpoch;
      for (var index = 0; index < _newPhotos.length; index++) {
        final photo = _newPhotos[index];
        final path =
            '${user.id}/$entryId/photo-$stamp-$index.${_extension(photo.name)}';
        await widget.repository.uploadPhoto(
          path: path,
          bytes: photo.bytes,
          contentType: photo.contentType,
        );
        uploadedPaths.add(path);
        uploadedNewPhotos[photo.id] = path;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final wasPublished = widget.entry?.isPublished == true;
      final publishedAt = publish
          ? wasPublished
                ? widget.entry?.publishedAt?.toUtc().toIso8601String() ?? now
                : now
          : null;
      final payload = <String, dynamic>{
        'title': title,
        'category': historyCategoryToDatabaseValue(_category),
        'person_name': _nullable(_person.text),
        'position': _nullable(_position.text),
        'start_year': start,
        'end_year': end,
        'biography': _nullable(_biography.text),
        'cover_photo_path': coverPath,
        'display_order': order ?? 0,
        'is_published': publish,
        'published_at': publishedAt,
      };

      if (widget.entry == null) {
        await widget.repository.insertEntry({
          'id': entryId,
          ...payload,
          'created_by': user.id,
        });
        entryInserted = true;
        entrySaved = true;
      } else {
        await widget.repository.updateEntry(entryId, payload);
        entrySaved = true;
      }

      if (_deletedPhotoIds.isNotEmpty) {
        await widget.repository.deletePhotoRows(_deletedPhotoIds);
      }

      for (var index = 0; index < _existingPhotos.length; index++) {
        final photo = _existingPhotos[index];
        await widget.repository.updatePhoto(
          photo.id,
          caption: _nullable(photo.caption.text),
          displayOrder: index,
        );
      }

      var nextOrder = _existingPhotos.length;
      for (final photo in _newPhotos) {
        await widget.repository.insertPhoto({
          'entry_id': entryId,
          'storage_path': uploadedNewPhotos[photo.id],
          'caption': _nullable(photo.caption.text),
          'display_order': nextOrder++,
        });
      }

      // The database is authoritative. Now remove files that are no longer
      // referenced, without failing a successful save if Storage hiccups.
      if (_existingCoverPath != null && coverPath != _existingCoverPath) {
        try {
          await widget.repository.removePhotos([_existingCoverPath!]);
        } catch (error) {
          debugPrint('Old cover could not be removed: $error');
        }
      }
      if (_deletedPhotoPaths.isNotEmpty) {
        try {
          await widget.repository.removePhotos(_deletedPhotoPaths);
        } catch (error) {
          debugPrint('Removed gallery files could not be cleaned up: $error');
        }
      }

      if (!mounted) return;
      _dirty = false;
      Navigator.of(context).pop(true);
    } catch (error) {
      // Do not leave newly uploaded files behind when no database row
      // references them. Once an existing record has been updated, the new
      // cover path is already stored, so the files must stay.
      var entryRemoved = false;
      if (entryInserted) {
        try {
          await widget.repository.deleteEntry(entryId);
          entryRemoved = true;
        } catch (cleanupError) {
          debugPrint(
            'Failed history entry could not be removed: $cleanupError',
          );
        }
      }
      final filesAreReferenced = entryInserted ? !entryRemoved : entrySaved;
      if (uploadedPaths.isNotEmpty && !filesAreReferenced) {
        try {
          await widget.repository.removePhotos(uploadedPaths);
        } catch (cleanupError) {
          debugPrint('Uploaded photos could not be cleaned up: $cleanupError');
        }
      }
      if (!mounted) return;
      setState(() => _saving = false);
      debugPrint('History entry save failed: ${_errorDetails(error)}');
      _message(_friendlySaveError(error));
      return;
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  int? _yearValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < 1800 || parsed > 2200) return null;
    return parsed;
  }

  String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _preview() async {
    if (_title.text.trim().isEmpty) {
      _message('Add a title before previewing the record.');
      return;
    }
    final photos = <_PreviewPhoto>[
      for (final photo in _existingPhotos)
        _PreviewPhoto(url: photo.url, caption: photo.caption.text.trim()),
      for (final photo in _newPhotos)
        _PreviewPhoto(bytes: photo.bytes, caption: photo.caption.text.trim()),
    ];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _EditorPreviewPage(
          title: _title.text.trim(),
          category: _category,
          personName: _nullable(_person.text),
          position: _nullable(_position.text),
          startYear: _yearValue(_startYear.text),
          endYear: _yearValue(_endYear.text),
          biography: _nullable(_biography.text),
          coverBytes: _coverRemoved ? null : _newCoverBytes,
          coverUrl: _coverRemoved ? null : _existingCoverUrl,
          photos: photos,
          published: _published,
        ),
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'Your unsaved changes to this archive record will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    }
  }

  String _friendlySaveError(Object error) {
    if (error is PostgrestException) {
      final message = error.message.toLowerCase();
      if (error.code == '42703' ||
          message.contains('does not exist') ||
          message.contains('column')) {
        return 'The archive database is out of date. Ask the church administrator to run the corrective migration, then try again.';
      }
      if (error.code == 'PGRST205' ||
          error.code == 'PGRST202' ||
          message.contains('schema cache') ||
          message.contains('could not find the table') ||
          message.contains('could not find the function')) {
        return 'The archive is not configured in Supabase yet. Ask the church administrator to run the corrective migration.';
      }
      if (error.code == '42501' ||
          message.contains('permission') ||
          message.contains('row-level security')) {
        return 'This account is not an active Media Team member. Ask a church administrator to activate it.';
      }
      if (error.code == '23502') {
        return 'A required field is missing. Add a title and try again.';
      }
      if (error.code == '23503') {
        return 'The record references data that no longer exists. Refresh and try again.';
      }
      final trimmed = error.message.trim();
      if (trimmed.isNotEmpty) {
        return 'The record could not be saved: $trimmed';
      }
    }
    if (error is StorageException) {
      final message = error.message.toLowerCase();
      if (message.contains('bucket') || message.contains('not found')) {
        return 'The church-history storage bucket is missing. Ask the church administrator to run the corrective migration.';
      }
      final trimmed = error.message.trim();
      if (trimmed.isNotEmpty) {
        return 'A photograph could not be uploaded: $trimmed';
      }
      return 'A photograph could not be uploaded. Check your connection and available storage, then try again.';
    }
    return 'The record could not be saved. Check your internet connection and try again.';
  }

  String _errorDetails(Object error) {
    if (error is PostgrestException) {
      return 'PostgrestException(code=${error.code}, message=${error.message}, '
          'details=${error.details}, hint=${error.hint})';
    }
    if (error is StorageException) {
      return 'StorageException(statusCode=${error.statusCode}, '
          'error=${error.error}, message=${error.message})';
    }
    return '${error.runtimeType}: $error';
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isEditing = widget.entry != null;
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_saving) {
          _message('Please wait for this record to finish saving.');
          return;
        }
        _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? 'Edit archive record' : 'New archive record'),
          actions: [
            IconButton(
              tooltip: 'Preview record',
              onPressed: _saving ? null : _preview,
              icon: const Icon(Icons.visibility_outlined),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
              children: [
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                _SectionCard(
                  title: 'The record',
                  subtitle: 'Names and years can stay empty for milestones and events.',
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: congregationHistoryCategories
                          .map(
                            (category) => DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _category = value;
                          _markDirty();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _title,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => _markDirty(),
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'A shepherd for a new season',
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _person,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => _markDirty(),
                            decoration: const InputDecoration(
                              labelText: 'Person’s name',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _position,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => _markDirty(),
                            decoration: const InputDecoration(
                              labelText: 'Position or role',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startYear,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _markDirty(),
                            decoration: const InputDecoration(
                              labelText: 'Start year',
                              hintText: '1998',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _endYear,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _markDirty(),
                            decoration: const InputDecoration(
                              labelText: 'End year',
                              hintText: 'Leave empty if ongoing',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _biography,
                      minLines: 5,
                      maxLines: 12,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => _markDirty(),
                      decoration: const InputDecoration(
                        labelText: 'Biography or historical description',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Cover photograph',
                  subtitle: 'A portrait or a defining moment for this record.',
                  children: [
                    if (_newCoverBytes != null)
                      _LocalImagePreview(bytes: _newCoverBytes!)
                    else if (_existingCoverUrl != null && !_coverRemoved)
                      SizedBox(
                        height: 190,
                        child: HistoryImage(url: _existingCoverUrl),
                      )
                    else
                      Container(
                        height: 130,
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            'No cover photograph',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _pickCover,
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _newCoverBytes == null &&
                                    !_coverRemoved &&
                                    _existingCoverUrl != null
                                ? 'Replace cover'
                                : 'Choose cover',
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_newCoverBytes != null ||
                            (_existingCoverPath != null && !_coverRemoved))
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                    _newCoverBytes = null;
                                    _newCoverName = null;
                                    _newCoverContentType = null;
                                    _coverRemoved = true;
                                    _markDirty();
                                  }),
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Gallery photographs',
                  subtitle: 'Add up to 20 photographs. Use the arrows to set the order members will see.',
                  children: [
                    if (_existingPhotos.isEmpty && _newPhotos.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.photo_library_outlined,
                              color: colors.onSurfaceVariant,
                              size: 30,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No gallery photographs yet',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    for (var index = 0; index < _existingPhotos.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ExistingPhotoEditorTile(
                          photo: _existingPhotos[index],
                          index: index,
                          count: _existingPhotos.length,
                          onChanged: _markDirty,
                          onMoveUp: index == 0
                              ? null
                              : () => _moveExistingPhoto(index, -1),
                          onMoveDown: index == _existingPhotos.length - 1
                              ? null
                              : () => _moveExistingPhoto(index, 1),
                          onRemove: _saving
                              ? null
                              : () => _removeExistingPhoto(
                                  _existingPhotos[index],
                                ),
                        ),
                      ),
                    for (var index = 0; index < _newPhotos.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _NewPhotoEditorTile(
                          photo: _newPhotos[index],
                          index: index,
                          count: _newPhotos.length,
                          onChanged: _markDirty,
                          onMoveUp: index == 0
                              ? null
                              : () => _moveNewPhoto(index, -1),
                          onMoveDown: index == _newPhotos.length - 1
                              ? null
                              : () => _moveNewPhoto(index, 1),
                          onRemove: _saving
                              ? null
                              : () => setState(() {
                                  final photo = _newPhotos.removeAt(index);
                                  photo.caption.dispose();
                                  _markDirty();
                                }),
                        ),
                      ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _addPhotos,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add gallery photographs'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Archive placement',
                  subtitle: 'A lower display order appears earlier in the member archive.',
                  children: [
                    TextField(
                      controller: _order,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _markDirty(),
                      decoration: const InputDecoration(
                        labelText: 'Display order',
                        prefixIcon: Icon(Icons.sort_rounded),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _save(publish: false),
                    child: Text(_published ? 'Unpublish' : 'Save draft'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(publish: true),
                    child: Text(_published ? 'Save changes' : 'Publish record'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _LocalImagePreview extends StatelessWidget {
  const _LocalImagePreview({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.memory(
        bytes,
        height: 190,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          height: 120,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

class _ExistingPhotoEditorTile extends StatelessWidget {
  const _ExistingPhotoEditorTile({
    required this.photo,
    required this.index,
    required this.count,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final _ExistingPhotoEditor photo;
  final int index;
  final int count;
  final VoidCallback onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return _PhotoEditorShell(
      index: index,
      count: count,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onRemove: onRemove,
      preview: SizedBox(
        width: 92,
        height: 72,
        child: HistoryImage(
          url: photo.url,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      caption: photo.caption,
      onChanged: onChanged,
    );
  }
}

class _NewPhotoEditorTile extends StatelessWidget {
  const _NewPhotoEditorTile({
    required this.photo,
    required this.index,
    required this.count,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final _NewPhotoEditor photo;
  final int index;
  final int count;
  final VoidCallback onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return _PhotoEditorShell(
      index: index,
      count: count,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onRemove: onRemove,
      preview: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          photo.bytes,
          width: 92,
          height: 72,
          fit: BoxFit.cover,
        ),
      ),
      caption: photo.caption,
      onChanged: onChanged,
    );
  }
}

class _PhotoEditorShell extends StatelessWidget {
  const _PhotoEditorShell({
    required this.index,
    required this.count,
    required this.preview,
    required this.caption,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final int index;
  final int count;
  final Widget preview;
  final TextEditingController caption;
  final VoidCallback onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          preview,
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: caption,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                hintText: 'Photograph caption',
                filled: false,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Move earlier',
                    onPressed: onMoveUp,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                  ),
                  IconButton(
                    tooltip: 'Move later',
                    onPressed: onMoveDown,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_downward_rounded, size: 17),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Remove photograph',
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: colors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExistingPhotoEditor {
  _ExistingPhotoEditor(CongregationHistoryPhoto photo)
    : id = photo.id,
      path = photo.storagePath,
      url = photo.url,
      caption = TextEditingController(text: photo.caption ?? '');

  final String id;
  final String path;
  final String? url;
  final TextEditingController caption;
}

class _NewPhotoEditor {
  _NewPhotoEditor({
    required this.bytes,
    required this.name,
    required this.contentType,
  }) : id = const Uuid().v4();

  final String id;
  final Uint8List bytes;
  final String name;
  final String contentType;
  final TextEditingController caption = TextEditingController();
}

class _PreviewPhoto {
  const _PreviewPhoto({this.url, this.bytes, required this.caption});

  final String? url;
  final Uint8List? bytes;
  final String caption;
}

class _EditorPreviewPage extends StatefulWidget {
  const _EditorPreviewPage({
    required this.title,
    required this.category,
    required this.personName,
    required this.position,
    required this.startYear,
    required this.endYear,
    required this.biography,
    required this.coverBytes,
    required this.coverUrl,
    required this.photos,
    required this.published,
  });

  final String title;
  final String category;
  final String? personName;
  final String? position;
  final int? startYear;
  final int? endYear;
  final String? biography;
  final Uint8List? coverBytes;
  final String? coverUrl;
  final List<_PreviewPhoto> photos;
  final bool published;

  @override
  State<_EditorPreviewPage> createState() => _EditorPreviewPageState();
}

class _EditorPreviewPageState extends State<_EditorPreviewPage> {
  int _page = 0;

  String? get _years {
    final start = widget.startYear;
    final end = widget.endYear;
    if (start == null && end == null) return null;
    if (start != null && end != null) {
      return start == end ? '$start' : '$start – $end';
    }
    if (start != null) return 'From $start';
    return 'Until $end';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final people = [
      if (widget.personName != null) widget.personName!,
      if (widget.position != null) widget.position!,
    ].join(' • ');
    return Scaffold(
      appBar: AppBar(title: const Text('Preview record')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 36),
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 17,
                      color: colors.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.published ? 'Preview of a published record.' : 'Preview only. This record is not visible to members until it is published.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _PreviewImage(
                url: widget.coverUrl,
                bytes: widget.coverBytes,
                height: 280,
                icon: historyCategoryIcon(widget.category),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  HistoryCategoryChip(category: widget.category),
                  const Spacer(),
                  if (_years != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        _years!,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                widget.title,
                style: const TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 32,
                  height: 1.14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (people.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  people,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
              if (widget.biography != null) ...[
                const SizedBox(height: 20),
                Text(
                  widget.biography!,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(height: 1.7),
                ),
              ],
              if (widget.photos.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Photographs',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 250,
                  child: PageView.builder(
                    itemCount: widget.photos.length,
                    onPageChanged: (value) => setState(() => _page = value),
                    itemBuilder: (context, index) {
                      final photo = widget.photos[index];
                      return _PreviewImage(
                        url: photo.url,
                        bytes: photo.bytes,
                        height: 230,
                        icon: Icons.photo_outlined,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                if (widget.photos[_page].caption.isNotEmpty)
                  Text(
                    widget.photos[_page].caption,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (widget.photos.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${_page + 1} of ${widget.photos.length}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({
    required this.url,
    required this.bytes,
    required this.height,
    required this.icon,
  });

  final String? url;
  final Uint8List? bytes;
  final double height;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(20);
    if (bytes != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(
          bytes!,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    }
    if (url != null) {
      return SizedBox(
        height: height,
        child: HistoryImage(url: url, placeholderIcon: icon),
      );
    }
    return Container(
      height: height * .6,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 42, color: colors.onSurfaceVariant),
    );
  }
}
