import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'tile_store.dart' if (dart.library.js_interop) 'tile_store_web.dart';

/// Map tiles, kept rather than fetched again.
///
/// A slippy map asks for the same two dozen images every time a finger moves,
/// and `Image.network` answered every one of them over the network: panning
/// back to where you just were re-downloaded the view you had a second ago.
/// On a technician's phone on mobile data that is the difference between a map
/// and a progress indicator.
///
/// Three tiers, in the order they are asked:
///
///   1. Flutter's own `ImageCache`, which holds *decoded* tiles and is reached
///      before this class is — [TileImage] keys on the URL, so a tile already
///      on screen costs nothing at all.
///   2. This memory tier, holding the encoded bytes. Small, because it exists
///      only to survive an `ImageCache` eviction without a round trip.
///   3. The disk, which survives the process. Not on the web, where the
///      browser's HTTP cache does the same job better.
///
/// A tile that cannot be had from any of them is not an error worth showing:
/// the map draws its own graticule underneath, and the tile simply does not
/// arrive.
class TileCache {
  TileCache._();

  static final TileCache instance = TileCache._();

  /// Encoded bytes only, and deliberately modest — the decoded copies in
  /// `ImageCache` are what the screen is actually drawing from, and holding
  /// both at full size would double the map's footprint for no gain.
  static const int memoryLimitBytes = 16 << 20;

  /// The ceiling the disk cache is trimmed back to at launch. Roughly two
  /// thousand tiles: a city's worth at the zooms a call-out is worked at.
  static const int diskLimitBytes = 96 << 20;

  /// Long, because a road that moved is a redraw nobody is waiting on, and
  /// short enough that a rebranded tile service reaches the field this month.
  static const Duration maxAge = Duration(days: 14);

  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List?>> _inFlight = <String, Future<Uint8List?>>{};
  int _memoryBytes = 0;
  bool _pruned = false;

  late final Dio _http = Dio(
    BaseOptions(
      responseType: ResponseType.bytes,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      // A tile service answering 404 for a tile it does not have is an ordinary
      // answer, not something to throw over.
      validateStatus: (status) => status != null && status < 500,
      headers: <String, String>{
        // OpenStreetMap's tile policy asks callers to identify themselves, and
        // refuses the ones that do not. A browser forbids overriding this
        // header and sends its own, so asking would only force a preflight the
        // tile service need not answer.
        if (!kIsWeb) 'User-Agent': 'ShirazTyres/2.0 (+support@shiraztyres.co.uk)',
      },
    ),
  );

  /// The bytes for one tile, from wherever they are cheapest.
  Future<Uint8List?> load(String url) {
    final key = _keyFor(url);

    final remembered = _memory.remove(key);
    if (remembered != null) {
      _memory[key] = remembered; // Re-inserted at the head: this is the LRU.
      return SynchronousFuture<Uint8List?>(remembered);
    }

    // Twenty tiles of one view can be asked for in the same frame, and a pan
    // asks for the row it is arriving at twice. One request each.
    return _inFlight[key] ??= _resolve(key, url).whenComplete(() => _inFlight.remove(key));
  }

  Future<Uint8List?> _resolve(String key, String url) async {
    if (tileDiskCacheAvailable) {
      final stored = await readTile(key, maxAge);
      if (stored != null) {
        _remember(key, stored);
        return stored;
      }
    }

    final bytes = await _download(url);
    if (bytes == null) return null;

    _remember(key, bytes);
    if (tileDiskCacheAvailable) {
      unawaited(writeTile(key, bytes));
      unawaited(_pruneOnce());
    }
    return bytes;
  }

  Future<Uint8List?> _download(String url) async {
    try {
      final response = await _http.get<List<int>>(url);
      final body = response.data;
      if (response.statusCode != 200 || body == null || body.isEmpty) return null;
      return Uint8List.fromList(body);
    } catch (_) {
      // No network, a refused tile, a service that has gone away. The map has
      // its graticule; a missing tile is not worth an error on screen.
      return null;
    }
  }

  void _remember(String key, Uint8List bytes) {
    // One oversized tile must not evict the whole cache to make room for itself.
    if (bytes.length > memoryLimitBytes ~/ 4) return;

    _memory.remove(key);
    _memory[key] = bytes;
    _memoryBytes += bytes.length;

    while (_memoryBytes > memoryLimitBytes && _memory.isNotEmpty) {
      final oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)?.length ?? 0;
    }
  }

  Future<void> _pruneOnce() async {
    if (_pruned) return;
    _pruned = true;
    await pruneTiles(maxBytes: diskLimitBytes, maxAge: maxAge);
  }

  /// A filename that is safe on every filesystem and cannot collide across tile
  /// services, without dragging in a hashing package for it.
  static String _keyFor(String url) {
    var hash = 0x811c9dc5;
    for (final unit in url.codeUnits) {
      hash = (hash ^ unit) * 0x01000193 & 0xffffffff;
    }
    final tail = url.length > 24 ? url.substring(url.length - 24) : url;
    final safe = tail.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    return '${hash.toRadixString(16).padLeft(8, '0')}_$safe';
  }

  /// The filename a URL is cached under. Exposed only so a test can prove two
  /// tiles never share one.
  @visibleForTesting
  static String keyForTile(String url) => _keyFor(url);

  /// Puts a tile of [bytes] bytes in the memory tier, so eviction can be tested
  /// without a network or a decoder.
  @visibleForTesting
  void debugRemember(String key, int bytes) => _remember(key, Uint8List(bytes));

  @visibleForTesting
  void clearMemory() {
    _memory.clear();
    _memoryBytes = 0;
    _inFlight.clear();
  }

  @visibleForTesting
  int get memoryCount => _memory.length;
}

/// A map tile as an [ImageProvider], so Flutter's decoded-image cache sits in
/// front of [TileCache] and the widget layer stays a plain [Image].
@immutable
class TileImage extends ImageProvider<TileImage> {
  const TileImage(this.url);

  final String url;

  @override
  Future<TileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<TileImage>(this);

  @override
  ImageStreamCompleter loadImage(TileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _decode(key, decode),
      scale: 1,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _decode(TileImage key, ImageDecoderCallback decode) async {
    final bytes = await TileCache.instance.load(key.url);
    if (bytes == null || bytes.isEmpty) {
      // Evicted, or the next pan would be answered from a cache entry that
      // knows only that the tile once failed.
      throw StateError('No tile for ${key.url}');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is TileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'TileImage($url)';
}
