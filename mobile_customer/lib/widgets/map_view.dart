import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/geo.dart';
import '../core/theme.dart';
import '../core/tile_cache.dart';

/// A slippy map, drawn from raster tiles when the build has a tile service and
/// from its own graticule when it has not.
///
/// It is deliberately small. All the picker needs is somewhere to pan, a zoom
/// that survives a pinch, and a background that makes a coordinate mean
/// something — which is a projection, a grid of images, and one gesture
/// recogniser. The alternative was a dependency with a map engine in it, for a
/// screen that shows one pin.

/// Where the map is looking. Held outside the widget so a screen can move it —
/// to a GPS fix, to a typed coordinate — while the gestures move it too.
class MapController extends ChangeNotifier {
  MapController({LatLng? centre, double zoom = 15})
      : _centre = centre ??
            const LatLng(AppConfig.mapFallbackLatitude, AppConfig.mapFallbackLongitude),
        _zoom = zoom;

  LatLng _centre;
  double _zoom;

  LatLng get centre => _centre;
  double get zoom => _zoom;

  static const minZoom = 3.0;
  static const maxZoom = 19.0;

  void moveTo(LatLng centre, {double? zoom}) {
    _centre = centre.normalised;
    if (zoom != null) _zoom = zoom.clamp(minZoom, maxZoom);
    notifyListeners();
  }

  void zoomBy(double delta) {
    _zoom = (_zoom + delta).clamp(minZoom, maxZoom);
    notifyListeners();
  }

  void _apply(LatLng centre, double zoom) {
    _centre = centre.normalised;
    _zoom = zoom.clamp(minZoom, maxZoom);
    notifyListeners();
  }
}

class MapView extends StatefulWidget {
  const MapView({
    required this.controller,
    this.interactive = true,
    this.onChanged,
    this.onDragging,
    super.key,
  });

  final MapController controller;

  /// A preview is not draggable; the picker is.
  final bool interactive;

  /// Fired on every settled move, so a screen can keep a coordinate readout in
  /// step with the map without listening to the controller itself.
  final ValueChanged<LatLng>? onChanged;

  /// True while a finger is on the map. The picker uses it to lift the pin, so
  /// the difference between "being moved" and "where it landed" is visible.
  final ValueChanged<bool>? onDragging;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late WorldPoint _gestureCentre;
  late double _gestureZoom;
  late Offset _gestureFocal;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(MapView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
    widget.onChanged?.call(widget.controller.centre);
  }

  void _start(ScaleStartDetails details) {
    _gestureCentre = projectToWorld(widget.controller.centre);
    _gestureZoom = widget.controller.zoom;
    _gestureFocal = details.localFocalPoint;
  }

  void _update(ScaleUpdateDetails details, Size size) {
    // Zoom about the fingers rather than the middle: the thing being looked at
    // stays under them, which is the whole difference between a map that feels
    // right and one that fights back.
    final zoom = (_gestureZoom + math.log(details.scale) / math.ln2)
        .clamp(MapController.minZoom, MapController.maxZoom);
    final startScale = math.pow(2, _gestureZoom).toDouble();
    final scale = math.pow(2, zoom).toDouble();
    final middle = Offset(size.width / 2, size.height / 2);

    final anchor = WorldPoint(
      _gestureCentre.x + (_gestureFocal.dx - middle.dx) / startScale,
      _gestureCentre.y + (_gestureFocal.dy - middle.dy) / startScale,
    );
    final focal = details.localFocalPoint;
    final centre = WorldPoint(
      anchor.x - (focal.dx - middle.dx) / scale,
      anchor.y - (focal.dy - middle.dy) / scale,
    );
    widget.controller._apply(unprojectFromWorld(centre), zoom);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ClipRRect(
      borderRadius: Radii.cardShape,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final layer = _TileLayer(
            centre: widget.controller.centre,
            zoom: widget.controller.zoom,
            size: size,
            palette: palette,
          );

          if (!widget.interactive) return layer;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (details) {
              widget.onDragging?.call(true);
              _start(details);
            },
            onScaleUpdate: (details) => _update(details, size),
            onScaleEnd: (_) => widget.onDragging?.call(false),
            onDoubleTapDown: (details) {
              _gestureCentre = projectToWorld(widget.controller.centre);
              _gestureZoom = widget.controller.zoom;
              _gestureFocal = details.localPosition;
              _update(
                ScaleUpdateDetails(localFocalPoint: details.localPosition, scale: 2),
                size,
              );
            },
            onDoubleTap: () {},
            child: layer,
          );
        },
      ),
    );
  }
}

/// The grid of tiles for one view, plus whatever the build has to draw them on.
class _TileLayer extends StatelessWidget {
  const _TileLayer({
    required this.centre,
    required this.zoom,
    required this.size,
    required this.palette,
  });

  final LatLng centre;
  final double zoom;
  final Size size;
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final url = AppConfig.mapTileUrl;
    final ground = CustomPaint(
      size: size,
      painter: _GraticulePainter(centre: centre, zoom: zoom, palette: palette),
    );
    if (url.isEmpty) return SizedBox.fromSize(size: size, child: ground);

    final level = zoom.floor().clamp(MapController.minZoom.toInt(), MapController.maxZoom.toInt());
    final scale = math.pow(2, zoom).toDouble();
    final span = tileSize / math.pow(2, level); // one tile, in zoom-0 pixels
    final onScreen = span * scale; // one tile, in device pixels
    final middle = Offset(size.width / 2, size.height / 2);
    final origin = projectToWorld(centre);

    final firstX = ((origin.x - middle.dx / scale) / span).floor();
    final lastX = ((origin.x + middle.dx / scale) / span).floor();
    final firstY = ((origin.y - middle.dy / scale) / span).floor();
    final lastY = ((origin.y + middle.dy / scale) / span).floor();
    final wrap = 1 << level;

    final tiles = <Widget>[];
    for (var x = firstX; x <= lastX; x++) {
      for (var y = firstY; y <= lastY; y++) {
        if (y < 0 || y >= wrap) continue;
        tiles.add(Positioned(
          left: (x * span - origin.x) * scale + middle.dx,
          top: (y * span - origin.y) * scale + middle.dy,
          // A hair of overlap, or a seam of background shows between tiles at
          // fractional zooms.
          width: onScreen + 1,
          height: onScreen + 1,
          child: _Tile(url: url, x: x % wrap < 0 ? x % wrap + wrap : x % wrap, y: y, z: level),
        ));
      }
    }

    return SizedBox.fromSize(
      size: size,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: <Widget>[
          Positioned.fill(child: ground),
          ...tiles,
          // Attribution belongs on screen wherever the tiles came from.
          Positioned(
            right: 6,
            bottom: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.canvas.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  AppConfig.mapAttribution,
                  style: TextStyle(
                    fontFamily: Fonts.sans,
                    fontSize: 9.5,
                    color: palette.inkMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.url, required this.x, required this.y, required this.z});

  final String url;
  final int x;
  final int y;
  final int z;

  @override
  Widget build(BuildContext context) {
    final source = url
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y')
        .replaceAll('{s}', 'a');

    // Through [TileCache] rather than straight at the network: panning back to
    // where you just were should not re-download the view you had a second ago.
    return Image(
      image: TileImage(source),
      fit: BoxFit.fill,
      gaplessPlayback: true,
      // A tile that will not load leaves the graticule showing through rather
      // than a broken-image glyph.
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      frameBuilder: (context, child, frame, wasSynchronous) {
        if (wasSynchronous || frame != null) {
          return AnimatedOpacity(
            opacity: 1,
            duration: Motion.fast,
            child: child,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// The map's own ground: a graticule of latitude and longitude, labelled, in the
/// app's colours. It is what a build with no tile service draws, and what shows
/// through while tiles are still arriving — so the picker is never a blank hole,
/// and a coordinate always has something to be read against.
class _GraticulePainter extends CustomPainter {
  const _GraticulePainter({required this.centre, required this.zoom, required this.palette});

  final LatLng centre;
  final double zoom;
  final Palette palette;

  /// A round number of degrees that puts roughly five lines across the view.
  static double _step(double degreesAcross) {
    const steps = <double>[10, 5, 2, 1, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001];
    for (final step in steps) {
      if (degreesAcross / step >= 4) return step;
    }
    return steps.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.surfaceSunken);

    final scale = math.pow(2, zoom).toDouble();
    final origin = projectToWorld(centre);
    final middle = Offset(size.width / 2, size.height / 2);

    Offset toScreen(LatLng point) {
      final world = projectToWorld(point);
      return Offset(
        (world.x - origin.x) * scale + middle.dx,
        (world.y - origin.y) * scale + middle.dy,
      );
    }

    final west = unprojectFromWorld(WorldPoint(origin.x - middle.dx / scale, origin.y));
    final east = unprojectFromWorld(WorldPoint(origin.x + middle.dx / scale, origin.y));
    final north = unprojectFromWorld(WorldPoint(origin.x, origin.y - middle.dy / scale));
    final south = unprojectFromWorld(WorldPoint(origin.x, origin.y + middle.dy / scale));

    final step = _step((east.longitude - west.longitude).abs());
    final line = Paint()
      ..color = palette.line
      ..strokeWidth = 1;

    void label(String text, Offset at) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: Fonts.mono,
            fontSize: 10,
            color: palette.inkSubtle,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, at);
    }

    for (var lng = (west.longitude / step).floor() * step; lng < east.longitude; lng += step) {
      final x = toScreen(LatLng(centre.latitude, lng)).dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      label(lng.toStringAsFixed(step < 0.01 ? 3 : 2), Offset(x + 3, size.height - 14));
    }
    for (var lat = (south.latitude / step).floor() * step; lat < north.latitude; lat += step) {
      final y = toScreen(LatLng(lat, centre.longitude)).dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      label(lat.toStringAsFixed(step < 0.01 ? 3 : 2), const Offset(4, 0) + Offset(0, y + 2));
    }
  }

  @override
  bool shouldRepaint(_GraticulePainter old) =>
      old.centre != centre || old.zoom != zoom || old.palette != palette;
}

/// A still map with a pin in the middle of it, for showing a location that has
/// already been chosen. Not draggable — tapping it is what opens the picker.
class MiniMap extends StatefulWidget {
  const MiniMap({required this.point, this.zoom = 16, this.height = 150, this.onTap, super.key});

  final LatLng point;
  final double zoom;
  final double height;
  final VoidCallback? onTap;

  @override
  State<MiniMap> createState() => _MiniMapState();
}

class _MiniMapState extends State<MiniMap> {
  late final MapController _controller =
      MapController(centre: widget.point, zoom: widget.zoom);

  @override
  void didUpdateWidget(MiniMap old) {
    super.didUpdateWidget(old);
    if (old.point != widget.point) _controller.moveTo(widget.point, zoom: widget.zoom);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            MapView(controller: _controller, interactive: false),
            const Center(child: MapPin(size: 34)),
            if (widget.onTap != null)
              Positioned(
                left: 8,
                top: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.canvas.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: Border.all(color: palette.line),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.edit_location_alt_outlined, size: 14, color: palette.gold),
                        const SizedBox(width: 5),
                        Text(
                          'Adjust',
                          style: TextStyle(
                            fontFamily: Fonts.sans,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: palette.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The marker itself: a gold drop with a hole in it, over a shadow that sits on
/// the ground where the point actually is. Drawn rather than an icon so the tip
/// lands exactly on the centre of the map.
class MapPin extends StatelessWidget {
  const MapPin({this.size = 46, this.lifted = false, super.key});

  final double size;

  /// Raised off the ground while the map is being dragged, which is what says
  /// "this is not where it lands yet".
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // The tip has to land on the exact centre of the box, because the box is
    // centred on the map and the tip is what the coordinate means. That holds
    // when the column's content is exactly twice the head's height, so the
    // trailing spacer is whatever is left over rather than a round number.
    return SizedBox(
      width: size,
      height: size * 2,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AnimatedSlide(
            duration: Motion.fast,
            offset: Offset(0, lifted ? -0.18 : 0),
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(painter: _PinPainter(palette)),
            ),
          ),
          const SizedBox(height: 2),
          AnimatedContainer(
            duration: Motion.fast,
            width: lifted ? size * 0.20 : size * 0.28,
            height: lifted ? size * 0.07 : size * 0.09,
            decoration: BoxDecoration(
              color: palette.ink.withValues(alpha: lifted ? 0.18 : 0.30),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
          ),
          SizedBox(height: size * 0.91 - 2),
        ],
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter(this.palette);

  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final radius = width * 0.36;
    final centre = Offset(width / 2, radius);
    final path = Path()
      ..addOval(Rect.fromCircle(center: centre, radius: radius))
      ..moveTo(width / 2 - radius * 0.55, radius * 1.5)
      ..lineTo(width / 2, size.height)
      ..lineTo(width / 2 + radius * 0.55, radius * 1.5)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = palette.ink.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(path, Paint()..color = palette.goldFill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = palette.onGold.withValues(alpha: 0.35),
    );
    canvas.drawCircle(centre, radius * 0.34, Paint()..color = palette.onGold);
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.palette != palette;
}
