import 'dart:math' as math;

/// A point on the earth, and the Web Mercator arithmetic the map draws it with.
///
/// Small enough to keep here rather than take a dependency for: the projection
/// is four lines, and owning it means the picker renders the same whether there
/// are tiles behind it or not.

class LatLng {
  const LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Clamped to what Mercator can express and to real coordinates, so a typed
  /// figure with a digit too many cannot put the map somewhere it cannot draw.
  LatLng get normalised => LatLng(
        latitude.clamp(-85.05112878, 85.05112878),
        longitude.clamp(-180.0, 180.0),
      );

  /// Six decimal places is about 0.1 m — past the point any phone can tell the
  /// difference, and what the API stores.
  String get pretty => '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  @override
  bool operator ==(Object other) =>
      other is LatLng && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => pretty;
}

/// The map's unit of work: pixels of a 256px world at zoom 0. Every other zoom
/// is this scaled by a power of two, which is what makes a pinch a multiply.
class WorldPoint {
  const WorldPoint(this.x, this.y);

  final double x;
  final double y;
}

const double tileSize = 256;

WorldPoint projectToWorld(LatLng point) {
  final clamped = point.normalised;
  final x = (clamped.longitude + 180) / 360 * tileSize;
  final sin = math.sin(clamped.latitude * math.pi / 180);
  final y = (0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * tileSize;
  return WorldPoint(x, y);
}

LatLng unprojectFromWorld(WorldPoint point) {
  final longitude = point.x / tileSize * 360 - 180;
  final n = math.pi - 2 * math.pi * point.y / tileSize;
  final latitude = 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  return LatLng(latitude, longitude).normalised;
}

/// Great-circle distance in metres. Used to say how far a pin has been moved
/// from the phone's own idea of where it is.
double metresBetween(LatLng a, LatLng b) {
  const radius = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
  return 2 * radius * math.asin(math.min(1, math.sqrt(h)));
}

/// Reads a coordinate somebody has typed or pasted. Accepts the shapes that
/// actually turn up — "51.5074, -0.1278", a maps.google URL's pair, a lone pair
/// separated by a space — and rejects everything else rather than guessing.
LatLng? parseLatLng(String input) {
  final matches = RegExp(r'-?\d{1,3}(?:\.\d+)?').allMatches(input).toList();
  if (matches.length < 2) return null;
  final latitude = double.tryParse(matches[0].group(0)!);
  final longitude = double.tryParse(matches[1].group(0)!);
  if (latitude == null || longitude == null) return null;
  if (latitude.abs() > 90 || longitude.abs() > 180) return null;
  return LatLng(latitude, longitude);
}
