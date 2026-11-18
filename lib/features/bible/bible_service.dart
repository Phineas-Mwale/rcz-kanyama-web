import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/bible_catalog_service.dart';
import 'data/bible_local_store.dart';
import 'data/bible_package_installer.dart';
import 'domain/bible_repository.dart';

/// One shared service for the Bible library, downloader and reader.
class BibleService {
  BibleService._({
    required this.catalog,
    required this.store,
    required this.installer,
    required this.repository,
  });

  final BibleCatalogService catalog;
  final BibleLocalStore store;
  final BiblePackageInstallerImpl installer;
  final BibleRepository repository;

  static Future<BibleService>? _shared;

  /// Opens the on-device library once. A failed open is not cached, so the
  /// library can be retried after a transient storage problem.
  static Future<BibleService> create(SupabaseClient client) async {
    final existing = _shared;
    if (existing != null) return existing;
    final pending = _open(client);
    _shared = pending;
    try {
      return await pending;
    } catch (_) {
      if (identical(_shared, pending)) _shared = null;
      rethrow;
    }
  }

  static Future<BibleService> _open(SupabaseClient client) async {
    final catalog = BibleCatalogService(client);
    final store = await BibleLocalStore.open();
    final installer = BiblePackageInstallerImpl(catalog: catalog, store: store);
    return BibleService._(
      catalog: catalog,
      store: store,
      installer: installer,
      repository: BibleRepository(store),
    );
  }
}
