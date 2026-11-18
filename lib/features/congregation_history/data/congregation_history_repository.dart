import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/congregation_history_models.dart';

/// Reads and writes the Kanyama Congregation History archive.
///
/// Only published rows are returned to members. Media Team calls use the same
/// repository but rely on Supabase RLS for the additional permissions.
class CongregationHistoryRepository {
  CongregationHistoryRepository(this._client);

  final SupabaseClient _client;

  static const bucket = 'church-history';

  Future<List<CongregationHistoryEntry>> fetchPublishedEntries() {
    return _fetchEntries(publishedOnly: true);
  }

  Future<List<CongregationHistoryEntry>> fetchAllEntries() {
    return _fetchEntries(publishedOnly: false);
  }

  Future<List<CongregationHistoryEntry>> _fetchEntries({
    required bool publishedOnly,
  }) async {
    var query = _client.from('church_history_entries').select();
    if (publishedOnly) {
      query = query.eq('is_published', true);
    }
    final rawEntries = await query
        .order('display_order', ascending: true)
        .order('start_year', ascending: true, nullsFirst: false)
        .order('created_at', ascending: true);

    final entries = rawEntries
        .map((row) => CongregationHistoryEntry.fromJson(row))
        .where((entry) => entry.id.isNotEmpty)
        .toList(growable: false);
    if (entries.isEmpty) return const [];

    final photosByEntry = <String, List<CongregationHistoryPhoto>>{};
    try {
      final rawPhotos = await _client
          .from('church_history_photos')
          .select()
          .inFilter('entry_id', entries.map((entry) => entry.id).toList())
          .order('display_order', ascending: true)
          .order('created_at', ascending: true);
      for (final row in rawPhotos) {
        final photo = CongregationHistoryPhoto.fromJson(row);
        if (photo.entryId.isEmpty) continue;
        photosByEntry.putIfAbsent(photo.entryId, () => []).add(photo);
      }
    } catch (error) {
      // An entry without gallery rows is still a valid archive record.
      debugPrint('History photos could not be loaded: $error');
    }

    final withPhotos = entries
        .map(
          (entry) => CongregationHistoryEntry(
            id: entry.id,
            title: entry.title,
            category: entry.category,
            personName: entry.personName,
            position: entry.position,
            startYear: entry.startYear,
            endYear: entry.endYear,
            biography: entry.biography,
            coverPhotoPath: entry.coverPhotoPath,
            displayOrder: entry.displayOrder,
            isPublished: entry.isPublished,
            publishedAt: entry.publishedAt,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            photos: photosByEntry[entry.id] ?? const [],
          ),
        )
        .toList(growable: false);

    final paths = <String>{
      for (final entry in withPhotos) ...entry.allPhotoPaths,
    };
    final urls = await signedUrls(paths);
    return withPhotos
        .map((entry) => entry.withMedia(urls))
        .toList(growable: false);
  }

  /// Creates short-lived URLs for a private bucket. A missing or unauthorised
  /// object is simply omitted so the UI can show its placeholder.
  Future<Map<String, String>> signedUrls(Iterable<String> paths) async {
    final unique = paths.where((path) => path.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return const {};
    try {
      final results = await _client.storage
          .from(bucket)
          .createSignedUrlsResult(unique, 3600);
      return {
        for (final result in results)
          if (result is SignedUrlSuccess) result.path: result.signedUrl,
      };
    } catch (error) {
      debugPrint('History photo signing failed: $error');
      return const {};
    }
  }

  Future<String> uploadPhoto({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }

  Future<void> removePhotos(Iterable<String> paths) async {
    final unique = paths.where((path) => path.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return;
    await _client.storage.from(bucket).remove(unique);
  }

  Future<void> insertEntry(Map<String, dynamic> values) async {
    await _client.from('church_history_entries').insert(values);
  }

  Future<void> updateEntry(String id, Map<String, dynamic> values) async {
    await _client.from('church_history_entries').update(values).eq('id', id);
  }

  Future<void> deleteEntry(String id) async {
    await _client.from('church_history_entries').delete().eq('id', id);
  }

  Future<void> updateDisplayOrder(String id, int order) async {
    await _client
        .from('church_history_entries')
        .update({'display_order': order})
        .eq('id', id);
  }

  Future<void> insertPhoto(Map<String, dynamic> values) async {
    await _client.from('church_history_photos').insert(values);
  }

  Future<void> updatePhoto(
    String id, {
    required String? caption,
    required int displayOrder,
  }) async {
    await _client
        .from('church_history_photos')
        .update({'caption': caption, 'display_order': displayOrder})
        .eq('id', id);
  }

  Future<void> deletePhotoRows(Iterable<String> ids) async {
    final unique = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return;
    await _client.from('church_history_photos').delete().inFilter('id', unique);
  }
}
