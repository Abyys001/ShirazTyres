import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// The on-disk half of [TileCache], on every platform that has a disk.
///
/// Tiles go in the temporary directory rather than application support: they
/// are derived data with an authoritative copy one request away, so the OS
/// reclaiming them under pressure is the correct outcome, not data loss.
///
/// Nothing here throws. A cache that cannot be read is a slower map; a cache
/// that can take the map down with it would be worse than having none.

const _folder = 'shiraztyres_map_tiles';

Directory? _resolved;
Future<Directory?>? _opening;

Future<Directory?> _directory() {
  if (_resolved != null) return Future<Directory?>.value(_resolved);
  return _opening ??= () async {
    try {
      // Bounded, because this is a platform channel and every tile on screen is
      // waiting behind it. A cache that cannot say where it lives inside five
      // seconds is one to go around, not one to hold the map up for.
      final base = await getTemporaryDirectory()
          .timeout(const Duration(seconds: 5), onTimeout: () => throw const _NoCacheDirectory());
      final directory = Directory('${base.path}/$_folder');
      if (!directory.existsSync()) await directory.create(recursive: true);
      return _resolved = directory;
    } catch (_) {
      return null;
    }
  }();
}

class _NoCacheDirectory implements Exception {
  const _NoCacheDirectory();
}

bool get tileDiskCacheAvailable => true;

Future<Uint8List?> readTile(String key, Duration maxAge) async {
  try {
    final directory = await _directory();
    if (directory == null) return null;
    final file = File('${directory.path}/$key');
    if (!file.existsSync()) return null;

    // A stale tile is still a tile. Roads do not move often, and showing
    // yesterday's London beats showing a hole while the network decides.
    // It is returned and refreshed behind the screen rather than withheld.
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    if (DateTime.now().difference(file.lastModifiedSync()) > maxAge) {
      unawaited(file.delete().catchError((_) => file));
      return null;
    }
    return bytes;
  } catch (_) {
    return null;
  }
}

Future<void> writeTile(String key, Uint8List bytes) async {
  try {
    final directory = await _directory();
    if (directory == null) return;
    // Written beside and renamed, so a process that dies mid-write leaves no
    // half a PNG to be read back as a corrupt tile forever after.
    final partial = File('${directory.path}/$key.part');
    await partial.writeAsBytes(bytes, flush: false);
    await partial.rename('${directory.path}/$key');
  } catch (_) {
    // Out of space, or a directory the sandbox withdrew. Either way the tile
    // is already on screen; only the next pan pays for it again.
  }
}

/// Oldest first, until the cache is back under its ceiling. Called once per
/// launch, off the first frame, because a cache nobody ever trims is a disk
/// leak with a friendly name.
Future<void> pruneTiles({required int maxBytes, required Duration maxAge}) async {
  try {
    final directory = await _directory();
    if (directory == null) return;

    final now = DateTime.now();
    final files = <({File file, DateTime at, int size})>[];
    var total = 0;

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = entity.statSync();
        if (now.difference(stat.modified) > maxAge || entity.path.endsWith('.part')) {
          await entity.delete();
          continue;
        }
        total += stat.size;
        files.add((file: entity, at: stat.modified, size: stat.size));
      } catch (_) {
        continue;
      }
    }

    if (total <= maxBytes) return;
    files.sort((a, b) => a.at.compareTo(b.at));
    for (final entry in files) {
      if (total <= maxBytes) break;
      try {
        await entry.file.delete();
        total -= entry.size;
      } catch (_) {
        continue;
      }
    }
  } catch (_) {
    // A prune that fails costs disk, not correctness.
  }
}
