import 'dart:typed_data';

/// The web has no disk to keep tiles on, and does not need one: the browser's
/// own HTTP cache already holds them, keyed by URL and honouring the tile
/// service's `cache-control`, which is exactly what the native side is
/// reimplementing here. [TileCache]'s memory tier still applies.
bool get tileDiskCacheAvailable => false;

Future<Uint8List?> readTile(String key, Duration maxAge) async => null;

Future<void> writeTile(String key, Uint8List bytes) async {}

Future<void> pruneTiles({required int maxBytes, required Duration maxAge}) async {}
