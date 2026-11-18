import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bible_service.dart';

/// Coordinates the automatic, background download of Bible translations.
///
/// The actual download, SHA-256 verification and install are still performed by
/// [BiblePackageInstallerImpl]. This class only decides *when* a translation
/// should be fetched, prevents duplicate work and exposes progress to the UI.
class BibleDownloadManager extends ChangeNotifier {
  BibleDownloadManager._(this._service, this._preferences);

  static const _autoDownloadKey = 'bible_auto_download_enabled';
  static const _wifiOnlyKey = 'bible_auto_download_wifi_only';
  static const _skippedKey = 'bible_auto_download_skipped';

  final BibleService _service;
  final SharedPreferences _preferences;

  static Future<BibleDownloadManager>? _shared;

  static Future<BibleDownloadManager> create({
    required SupabaseClient client,
    required SharedPreferences preferences,
  }) async {
    final existing = _shared;
    if (existing != null) return existing;
    final pending = _open(client, preferences);
    _shared = pending;
    try {
      return await pending;
    } catch (_) {
      if (identical(_shared, pending)) _shared = null;
      rethrow;
    }
  }

  static Future<BibleDownloadManager> _open(
    SupabaseClient client,
    SharedPreferences preferences,
  ) async {
    final service = await BibleService.create(client);
    return BibleDownloadManager._(service, preferences);
  }

  BibleService get service => _service;

  bool get autoDownloadEnabled =>
      _preferences.getBool(_autoDownloadKey) ?? true;

  bool get wifiOnly => _preferences.getBool(_wifiOnlyKey) ?? true;

  bool _running = false;
  bool _checkedThisSession = false;
  String? _activeTranslationId;
  String? _activeTranslationName;
  double _activeProgress = 0;
  int _completed = 0;
  int _total = 0;
  BibleDownloadState _state = BibleDownloadState.idle;
  String? _message;
  final Set<String> _failedThisSession = <String>{};

  bool get running => _running;
  bool get checkedThisSession => _checkedThisSession;
  String? get activeTranslationId => _activeTranslationId;
  String? get activeTranslationName => _activeTranslationName;
  double get activeProgress => _activeProgress;
  int get completed => _completed;
  int get total => _total;
  BibleDownloadState get state => _state;
  String? get message => _message;
  Set<String> get failedTranslationIds =>
      Set<String>.unmodifiable(_failedThisSession);

  Set<String> get _skippedIds =>
      (_preferences.getStringList(_skippedKey) ?? const []).toSet();

  bool get hasSkippedTranslations => _skippedIds.isNotEmpty;

  /// A manually removed translation must not silently return on the next app
  /// launch. Choosing "Download" again clears this preference.
  Future<void> skipAutomaticDownload(String translationId) async {
    final skipped = _skippedIds..add(translationId);
    await _preferences.setStringList(
      _skippedKey,
      skipped.toList(growable: false),
    );
    _failedThisSession.remove(translationId);
    notifyListeners();
  }

  Future<void> allowAutomaticDownload(String translationId) async {
    final skipped = _skippedIds..remove(translationId);
    await _preferences.setStringList(
      _skippedKey,
      skipped.toList(growable: false),
    );
    notifyListeners();
  }

  Future<void> setAutoDownloadEnabled(bool value) async {
    await _preferences.setBool(_autoDownloadKey, value);
    if (!value) {
      _state = BibleDownloadState.disabled;
      _message = 'Automatic Bible downloads are turned off.';
      notifyListeners();
      return;
    }
    _state = BibleDownloadState.idle;
    _message = null;
    _checkedThisSession = true;
    notifyListeners();
    await runAutomatic();
  }

  Future<void> setWifiOnly(bool value) async {
    await _preferences.setBool(_wifiOnlyKey, value);
    notifyListeners();
    if (!value && _state == BibleDownloadState.waitingForWifi) {
      await runAutomatic();
    }
  }

  /// Starts once per app session. It is safe to call repeatedly.
  Future<void> startIfNeeded() async {
    if (_checkedThisSession) return;
    _checkedThisSession = true;
    await runAutomatic();
  }

  /// Retries translations that failed earlier in this session.
  Future<void> retryFailed() async {
    if (_failedThisSession.isEmpty) {
      await runAutomatic();
      return;
    }
    _failedThisSession.clear();
    await runAutomatic();
  }

  /// Downloads every available translation that is not yet installed.
  ///
  /// Failures are kept per translation and never interrupt the whole library.
  /// No dialog is shown: the Bible library surfaces a quiet status line.
  Future<void> runAutomatic() async {
    if (_running) return;
    if (!autoDownloadEnabled) {
      _state = BibleDownloadState.disabled;
      _message = 'Automatic Bible downloads are turned off.';
      notifyListeners();
      return;
    }

    _running = true;
    _state = BibleDownloadState.checking;
    _message = 'Checking for translations that are ready offline…';
    _completed = 0;
    _total = 0;
    notifyListeners();

    try {
      final connection = await _connectionStatus();
      if (connection == _ConnectionStatus.offline) {
        _state = BibleDownloadState.offline;
        _message = 'No internet connection. Downloaded Bibles still work.';
        return;
      }
      if (wifiOnly && connection == _ConnectionStatus.mobile) {
        _state = BibleDownloadState.waitingForWifi;
        _message = 'Waiting for Wi-Fi. Turn on mobile downloads in the Bible library to download now.';
        return;
      }

      final catalog = await _service.catalog.fetchCatalog();
      final installed = (await _service.store.installedTranslationIds())
          .toSet();
      final skipped = _skippedIds;
      final candidates = catalog
          .where(
            (translation) =>
                translation.isAvailable &&
                !installed.contains(translation.id) &&
                !skipped.contains(translation.id) &&
                !_failedThisSession.contains(translation.id),
          )
          .toList(growable: false);

      if (candidates.isEmpty) {
        _state = BibleDownloadState.ready;
        if (!catalog.any((translation) => translation.isAvailable)) {
          _message = 'No translations are available for download yet.';
        } else if (skipped.isEmpty) {
          _message =
              'Every available translation is ready for offline reading.';
        } else {
          _message = 'You are up to date. Removed translations stay off until you download them again.';
        }
        return;
      }

      _total = candidates.length;
      _state = BibleDownloadState.downloading;

      var cancelled = false;
      for (final translation in candidates) {
        if (!autoDownloadEnabled) {
          _state = BibleDownloadState.disabled;
          _message = 'Automatic Bible downloads were turned off.';
          cancelled = true;
          break;
        }
        if (_skippedIds.contains(translation.id)) continue;
        // A manual download may have finished while this queue was running.
        final installedNow = await _service.store.installedTranslationIds();
        if (installedNow.contains(translation.id)) continue;

        _activeTranslationId = translation.id;
        _activeTranslationName = translation.shortName;
        _activeProgress = 0;
        notifyListeners();

        var succeeded = false;
        Object? lastError;
        for (var attempt = 0; attempt < 3 && !succeeded; attempt++) {
          try {
            await _service.installer.install(
              translationId: translation.id,
              packageUrl: translation.packagePath!,
              expectedSha256: translation.sha256!,
              onProgress: (value) {
                _activeProgress = value;
                notifyListeners();
              },
            );
            succeeded = true;
          } catch (error) {
            lastError = error;
            if (attempt < 2) {
              await Future<void>.delayed(
                Duration(milliseconds: 700 * (attempt + 1)),
              );
            }
          }
        }

        if (succeeded) {
          _service.repository.clearCache();
          _completed += 1;
        } else {
          _failedThisSession.add(translation.id);
          debugPrint(
            'Automatic Bible download failed for ${translation.id}: $lastError',
          );
        }
        _activeTranslationId = null;
        _activeTranslationName = null;
        _activeProgress = 0;
        notifyListeners();
      }

      if (!cancelled) {
        _message = _failedThisSession.isEmpty
            ? 'Bible downloads are complete.'
            : 'Some translations could not be downloaded. You can retry from the Bible library.';
        _state = _failedThisSession.isEmpty
            ? BibleDownloadState.ready
            : BibleDownloadState.failed;
      }
    } catch (error) {
      debugPrint('Bible download check failed: $error');
      _state = BibleDownloadState.failed;
      _message = 'Bible downloads could not be checked. Check your connection and try again.';
    } finally {
      _running = false;
      _activeTranslationId = null;
      _activeTranslationName = null;
      _activeProgress = 0;
      notifyListeners();
    }
  }

  Future<_ConnectionStatus> _connectionStatus() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.none)) {
        return _ConnectionStatus.offline;
      }
      if (results.contains(ConnectivityResult.mobile) &&
          !results.contains(ConnectivityResult.wifi) &&
          !results.contains(ConnectivityResult.ethernet)) {
        return _ConnectionStatus.mobile;
      }
      return _ConnectionStatus.unmetered;
    } catch (error) {
      // Some desktop/test environments do not implement connectivity. A
      // catalogue fetch is still attempted and will fail safely if offline.
      debugPrint('Connectivity check unavailable: $error');
      return _ConnectionStatus.unknown;
    }
  }
}

enum BibleDownloadState {
  idle,
  checking,
  downloading,
  ready,
  disabled,
  offline,
  waitingForWifi,
  failed,
}

enum _ConnectionStatus { offline, mobile, unmetered, unknown }
