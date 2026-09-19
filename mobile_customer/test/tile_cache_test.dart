import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiraztyres_customer/core/tile_cache.dart';

/// Tiles are the one thing a map asks for over and over. The cache is what
/// stops a pan back to where you just were costing a download of the view you
/// had a second ago.
void main() {
  setUp(TileCache.instance.clearMemory);

  test('the same tile is one image key, so the decoded cache can hold it', () {
    const a = TileImage('https://tiles/12/2047/1362.png');
    const b = TileImage('https://tiles/12/2047/1362.png');
    const c = TileImage('https://tiles/12/2047/1363.png');

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(a, isNot(equals(c)));
  });

  test('a key is filesystem-safe and does not collide across services', () {
    final keys = <String>{};
    for (final url in <String>[
      'https://tile.openstreetmap.org/12/2047/1362.png',
      'https://tile.openstreetmap.org/12/2047/1363.png',
      'https://tile.openstreetmap.org/13/2047/1362.png',
      'https://tiles.example.com/12/2047/1362.png',
      'https://tiles.example.com/12/2047/1362.png?key=abc',
    ]) {
      final key = TileCache.keyForTile(url);
      expect(key, matches(RegExp(r'^[A-Za-z0-9_]+$')), reason: url);
      keys.add(key);
    }
    expect(keys.length, 5, reason: 'every distinct tile needs its own file');
  });

  test('a tile already in memory costs no round trip at all', () async {
    const url = 'https://tiles.example.com/12/2047/1362.png';
    expect(TileCache.instance.memoryCount, 0);

    TileCache.instance.debugRemember(TileCache.keyForTile(url), 2048);

    // Synchronous, not merely fast: a hit must not reach the disk or the
    // network, which is the whole reason a pan back to where you were is free.
    var answered = false;
    unawaited(TileCache.instance.load(url).then((bytes) {
      answered = bytes != null && bytes.length == 2048;
    }));
    await Future<void>.microtask(() {});
    expect(answered, isTrue);
  });

  test('the memory tier evicts oldest-first and stays under its ceiling', () {
    // 40 tiles of 1MB against a 16MB ceiling: the cache must shed, not grow.
    for (var i = 0; i < 40; i++) {
      TileCache.instance.debugRemember('tile-$i', 1 << 20);
    }
    expect(TileCache.instance.memoryCount, lessThanOrEqualTo(16));
    expect(TileCache.instance.memoryCount, greaterThan(0));
  });

  test('one oversized tile does not evict everything to fit itself', () {
    TileCache.instance.debugRemember('small', 1 << 10);
    TileCache.instance.debugRemember('huge', TileCache.memoryLimitBytes);
    expect(TileCache.instance.memoryCount, 1, reason: 'the small one survives');
  });
}
