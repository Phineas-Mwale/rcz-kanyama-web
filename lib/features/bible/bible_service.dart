import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/bible_catalog_service.dart';
import 'data/bible_local_store.dart';
import 'data/bible_package_installer.dart';
import 'domain/bible_repository.dart';

/// One shared service for the Bible library, downloader and reader.
class BibleService {
  BibleService._({required this.catalog, required this.store, required this.installer, required this.repository});

  final BibleCatalogService catalog;
  final BibleLocalStore store;
  final BiblePackageInstallerImpl installer;
  final BibleRepository repository;

  static Future<BibleService>? _shared;

  static Future<BibleService> create(SupabaseClient client) {
    return _shared ??= _open(client);
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
