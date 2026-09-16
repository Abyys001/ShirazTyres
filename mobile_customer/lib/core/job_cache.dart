import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The last call-out the API confirmed, kept on the device.
///
/// A customer who closed the app on a live call-out reopens on that call-out,
/// signal or no signal. Without this, the first launch of the day was whatever
/// the network happened to be doing at that second — which, on a roadside with
/// one bar, was an error page where the job should have been.
///
/// Written as the raw JSON the API returned rather than as a decoded model, so
/// a field added to the payload later needs no migration here.
class JobCache {
  const JobCache(this._storage);

  final FlutterSecureStorage _storage;

  static const _activeKey = 'st_active_job';
  static const _historyKey = 'st_job_history';
  static const _stampKey = 'st_job_cached_at';

  /// The stored call-out, or null for "nothing cached" *and* for "cached the
  /// fact that there is none" — both mean the home screen shows the start
  /// button, so they do not need telling apart.
  Future<Map<String, dynamic>?> readActive() async {
    final raw = await _read(_activeKey);
    if (raw == null || raw.isEmpty || raw == 'null') return null;
    final decoded = _decode(raw);
    return decoded is Map ? decoded.map((key, value) => MapEntry('$key', value)) : null;
  }

  Future<void> writeActive(Map<String, dynamic>? job) async {
    await _write(_activeKey, job == null ? 'null' : jsonEncode(job));
    await _write(_stampKey, DateTime.now().toUtc().toIso8601String());
  }

  Future<List<Map<String, dynamic>>> readHistory() async {
    final raw = await _read(_historyKey);
    if (raw == null || raw.isEmpty) return const <Map<String, dynamic>>[];
    final decoded = _decode(raw);
    if (decoded is! List) return const <Map<String, dynamic>>[];
    return decoded
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry('$key', value)))
        .toList();
  }

  Future<void> writeHistory(List<Map<String, dynamic>> jobs) =>
      // Enough to fill the screen a cold start opens on; the rest is one
      // successful request away.
      _write(_historyKey, jsonEncode(jobs.take(20).toList()));

  /// When the cache was last confirmed, so the screen can say "as of" rather
  /// than present stale figures as live ones.
  Future<DateTime?> readStamp() async {
    final raw = await _read(_stampKey);
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  Future<void> clear() async {
    for (final key in const <String>[_activeKey, _historyKey, _stampKey]) {
      try {
        await _storage.delete(key: key);
      } on PlatformException {
        // Already unreadable, which is all the caller wanted.
      }
    }
  }

  static dynamic _decode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException {
      // A cache that cannot be written is a cache miss next launch, no more.
    }
  }
}
