import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks which published notices this device has opened.
///
/// SharedPreferences is the immediate, offline-safe source of truth. A
/// best-effort Supabase receipt is also written using the existing member
/// device id; if the optional RPC is unavailable, the local badge still works
/// and nothing is reported to the user as saved remotely.
class NoticeReadService {
  NoticeReadService(this._preferences);

  static const _storageKey = 'read_notice_ids';

  final SharedPreferences _preferences;
  Set<String>? _cached;
  bool _remoteMergeAttempted = false;
  Future<bool> _writeQueue = Future<bool>.value(true);

  Set<String> get _readIds {
    return _cached ??= {
      ...?_preferences.getStringList(_storageKey)?.map((id) => id.toString()),
    };
  }

  /// Serialises writes so two notices opened in quick succession cannot
  /// overwrite each other's saved state.
  Future<bool> _persistReadIds() {
    final operation = _writeQueue.then((_) async {
      try {
        return await _preferences.setStringList(
          _storageKey,
          _readIds.toList(growable: false),
        );
      } catch (error) {
        debugPrint('Notice read state could not be saved: $error');
        return false;
      }
    });
    _writeQueue = operation;
    return operation;
  }

  bool isRead(Object? noticeId) {
    if (noticeId == null) return false;
    return _readIds.contains(noticeId.toString());
  }

  int unreadCount(Iterable<Object?> noticeIds) {
    var count = 0;
    for (final id in noticeIds) {
      if (id != null && !_readIds.contains(id.toString())) count++;
    }
    return count;
  }

  /// Marks a notice as read on this device. Returns false only when the local
  /// write itself failed, so callers never reduce the badge on a failed save.
  Future<bool> markRead(Object? noticeId) async {
    if (noticeId == null) return false;
    final id = noticeId.toString();
    if (_readIds.contains(id)) return true;
    _readIds.add(id);
    final saved = await _persistReadIds();
    if (!saved) {
      _readIds.remove(id);
      return false;
    }
    unawaited(_syncReceipt(id));
    return true;
  }

  /// Merges receipts stored on the server for this same device id. This is
  /// optional and silently ignored when the corrective SQL has not been run.
  Future<void> mergeRemoteReceipts() async {
    if (_remoteMergeAttempted) return;
    _remoteMergeAttempted = true;
    final deviceId = _preferences.getString('device_id');
    if (deviceId == null || deviceId.isEmpty) return;
    try {
      final response = await Supabase.instance.client.rpc(
        'get_notice_reads',
        params: {'p_device_id': deviceId},
      );
      if (response is! List) return;
      var changed = false;
      for (final value in response) {
        if (value == null) continue;
        changed = _readIds.add(value.toString()) || changed;
      }
      if (changed) {
        await _persistReadIds();
      }
    } catch (error) {
      debugPrint('Remote notice receipts unavailable: $error');
    }
  }

  Future<void> _syncReceipt(String noticeId) async {
    final deviceId = _preferences.getString('device_id');
    final id = noticeId.trim();
    if (deviceId == null || deviceId.isEmpty || id.isEmpty) return;
    try {
      await Supabase.instance.client.rpc(
        'mark_notice_read',
        params: {'p_device_id': deviceId, 'p_notice_id': id},
      );
    } catch (error) {
      // Local persistence already succeeded. Never surface this as a failure.
      debugPrint('Notice receipt could not be synced: $error');
    }
  }
}
