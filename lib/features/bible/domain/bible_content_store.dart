/// Storage boundary shared by Android, iOS and browser IndexedDB.
abstract interface class BibleContentStore {
  Future<String> readManifestJson(String translationId);
  Future<String> readChapterJson({required String translationId, required String bookId, required int chapter});
  Future<bool> isTranslationInstalled(String translationId);
  Future<List<String>> installedTranslationIds();
}

abstract interface class BiblePackageInstaller {
  Future<void> install({required String translationId, required String packageUrl, required String expectedSha256, required void Function(double progress) onProgress});
  Future<void> uninstall(String translationId);
}
