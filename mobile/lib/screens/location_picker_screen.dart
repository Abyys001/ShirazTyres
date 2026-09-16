import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/geo.dart';
import '../core/location.dart';
import '../core/theme.dart';
import '../widgets/map_view.dart';
import '../widgets/ui_kit.dart';

/// What the picker hands back: a point, how it was arrived at, and whatever the
/// person typed alongside it.
class PickedLocation {
  const PickedLocation({required this.point, required this.source, this.note = ''});

  final LatLng point;
  final FixSource source;

  /// The landmark line. Kept with the point because the two are one answer to
  /// "where are you" — a coordinate gets a van to the road, the note gets it to
  /// the right side of it.
  final String note;

  LocationResult get asResult => source == FixSource.pin
      ? LocationResult.pinned(point)
      : LocationResult(latitude: point.latitude, longitude: point.longitude);
}

/// Opens the picker and returns what was chosen, or null if it was backed out of.
Future<PickedLocation?> pickLocation(
  BuildContext context, {
  LatLng? initial,
  String note = '',
  String title = 'Set the location',
  String confirmLabel = 'Use this spot',
  String prompt = 'Drag the map until the pin is on you.',
  bool askForNote = true,
}) {
  return Navigator.of(context).push<PickedLocation>(
    MaterialPageRoute<PickedLocation>(
      fullscreenDialog: true,
      builder: (_) => LocationPickerScreen(
        initial: initial,
        note: note,
        title: title,
        confirmLabel: confirmLabel,
        prompt: prompt,
        askForNote: askForNote,
      ),
    ),
  );
}

/// Pick a point by moving the map under a fixed pin.
///
/// The pin does not move; the world does. It is the one interaction that works
/// with a thumb on a phone held in one hand — a marker you have to drag ends up
/// under your finger exactly when you need to see it. Everything else on the
/// screen exists because the map alone is not always enough: the GPS button for
/// when the phone does know, and typed coordinates for when somebody has been
/// read them over the phone or has them from another app.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    this.initial,
    this.note = '',
    this.title = 'Set the location',
    this.confirmLabel = 'Use this spot',
    this.prompt = 'Drag the map until the pin is on you.',
    this.askForNote = true,
    super.key,
  });

  final LatLng? initial;
  final String note;
  final String title;
  final String confirmLabel;
  final String prompt;
  final bool askForNote;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late final MapController _map = MapController(
    centre: widget.initial,
    zoom: widget.initial == null ? 12 : 16.5,
  );
  late final TextEditingController _note = TextEditingController(text: widget.note);

  late LatLng _centre = _map.centre;
  bool _dragging = false;
  bool _locating = false;
  String? _error;

  /// The phone's own fix, once asked for. Kept so the pin can say how far it
  /// has been moved from it — the number that tells somebody whether they have
  /// dragged the map to the next street or the next town.
  LatLng? _deviceFix;

  @override
  void dispose() {
    _map.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Nothing was moved by hand and the pin is still sitting on the phone's own
  /// fix, so this is a device location rather than a pin.
  bool get _isDeviceFix =>
      _deviceFix != null && metresBetween(_deviceFix!, _centre) < 1;

  Future<void> _useGps() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    final fix = await currentLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _error = fix.error;
      if (fix.isFixed) _deviceFix = fix.point;
    });
    if (fix.isFixed) {
      Buzz.commit();
      _map.moveTo(fix.point!, zoom: 17);
    }
  }

  Future<void> _typeCoordinates() async {
    final typed = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CoordinateSheet(start: _centre),
    );
    if (typed == null || !mounted) return;
    setState(() => _error = null);
    _map.moveTo(typed, zoom: 16.5);
  }

  void _confirm() {
    Buzz.commit();
    Navigator.of(context).pop(
      PickedLocation(
        point: _centre,
        source: _isDeviceFix ? FixSource.device : FixSource.pin,
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final drift = _deviceFix == null ? null : metresBetween(_deviceFix!, _centre);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              // Expand, not loose: every other child here is positioned, so a
              // loose stack would shrink to the width of the pin.
              fit: StackFit.expand,
              children: <Widget>[
                MapView(
                  controller: _map,
                  onChanged: (centre) => setState(() => _centre = centre),
                  onDragging: (dragging) => setState(() => _dragging = dragging),
                ),

                // The pin sits on the exact centre of the map, so its tip and
                // the coordinate below are the same place by construction.
                IgnorePointer(child: Center(child: MapPin(lifted: _dragging))),

                Positioned(
                  left: Space.lg,
                  right: Space.lg,
                  top: Space.lg,
                  child: _Hint(text: widget.prompt),
                ),

                Positioned(
                  right: Space.lg,
                  bottom: Space.lg,
                  child: Column(
                    children: <Widget>[
                      _MapButton(
                        icon: Icons.add,
                        tooltip: 'Zoom in',
                        onTap: () => _map.zoomBy(1),
                      ),
                      const SizedBox(height: Space.sm),
                      _MapButton(
                        icon: Icons.remove,
                        tooltip: 'Zoom out',
                        onTap: () => _map.zoomBy(-1),
                      ),
                      const SizedBox(height: Space.lg),
                      _MapButton(
                        icon: Icons.my_location,
                        tooltip: 'Go to my location',
                        busy: _locating,
                        prominent: true,
                        onTap: _locating ? null : _useGps,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // The answer, spelled out, above the button that commits it.
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border(top: BorderSide(color: palette.line)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          _isDeviceFix ? Icons.gps_fixed : Icons.place_outlined,
                          size: 18,
                          color: palette.gold,
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Text(_centre.pretty, style: palette.mono.copyWith(color: palette.ink)),
                        ),
                        TextButton(
                          onPressed: _typeCoordinates,
                          child: const Text('Type it'),
                        ),
                      ],
                    ),
                    Text(
                      _isDeviceFix
                          ? 'This is your phone’s own fix.'
                          : drift == null
                              ? 'Set by hand on the map.'
                              : 'Set by hand · ${formatDistance(drift)} from your phone’s fix.',
                      style: theme.textTheme.bodySmall,
                    ),

                    if (_error != null) ...<Widget>[
                      const SizedBox(height: Space.md),
                      InlineNotice(_error!),
                    ],

                    if (widget.askForNote) ...<Widget>[
                      const SizedBox(height: Space.md),
                      TextField(
                        controller: _note,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Landmark (optional)',
                          hintText: 'Hard shoulder, past the Perivale exit',
                          prefixIcon: Icon(Icons.signpost_outlined),
                        ),
                      ),
                    ],

                    const SizedBox(height: Space.md),
                    FilledButton.icon(
                      onPressed: _confirm,
                      icon: const Icon(Icons.check, size: 20),
                      label: Text(widget.confirmLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Metres while it is still worth counting them, kilometres after.
String formatDistance(double metres) =>
    metres < 950 ? '${metres.round()} m' : '${(metres / 1000).toStringAsFixed(1)} km';

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.92),
        borderRadius: Radii.controlShape,
        border: Border.all(color: palette.line),
        boxShadow: palette.lift,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.touch_app_outlined, size: 18, color: palette.gold),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.3)),
          ),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.busy = false,
    this.prominent = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  /// The GPS button, which is the one thing on the map worth spending gold on.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: prominent ? palette.goldFill : palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.controlShape,
          side: BorderSide(color: prominent ? palette.goldFill : palette.line),
        ),
        elevation: 0,
        child: InkWell(
          borderRadius: Radii.controlShape,
          onTap: onTap == null
              ? null
              : () {
                  Buzz.tap();
                  onTap!();
                },
          child: SizedBox(
            width: 46,
            height: 46,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(13),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: prominent ? palette.onGold : palette.gold,
                    ),
                  )
                : Icon(icon, size: 22, color: prominent ? palette.onGold : palette.ink),
          ),
        ),
      ),
    );
  }
}

/// Typed coordinates, for when somebody has been given a pair rather than being
/// somewhere. Takes one pasted line as readily as two fields, because that is
/// how a location arrives in a text message.
class _CoordinateSheet extends StatefulWidget {
  const _CoordinateSheet({required this.start});

  final LatLng start;

  @override
  State<_CoordinateSheet> createState() => _CoordinateSheetState();
}

class _CoordinateSheetState extends State<_CoordinateSheet> {
  late final TextEditingController _latitude =
      TextEditingController(text: widget.start.latitude.toStringAsFixed(5));
  late final TextEditingController _longitude =
      TextEditingController(text: widget.start.longitude.toStringAsFixed(5));
  String? _error;

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  /// A pasted "51.5074, -0.1278" lands in the latitude field; splitting it
  /// across both is the app's job, not the person's.
  void _spread(String value) {
    final pair = parseLatLng(value);
    if (pair == null || !value.contains(RegExp('[,; ]'))) return;
    _latitude.text = pair.latitude.toStringAsFixed(5);
    _longitude.text = pair.longitude.toStringAsFixed(5);
  }

  void _apply() {
    final point = parseLatLng('${_latitude.text}, ${_longitude.text}');
    if (point == null) {
      setState(() => _error = 'Enter a latitude and a longitude, like 51.50740, -0.12780.');
      return;
    }
    Navigator.of(context).pop(point);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.xl,
        0,
        Space.xl,
        MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Type the coordinates', style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.xs),
          Text(
            'Paste a pair into either box and it will sort itself out.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _latitude,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  onChanged: _spread,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,\- ]')),
                  ],
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: TextField(
                  controller: _longitude,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  onChanged: _spread,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,\- ]')),
                  ],
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
              ),
            ],
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: Space.md),
            InlineNotice(_error!),
          ],
          const SizedBox(height: Space.lg),
          FilledButton(onPressed: _apply, child: const Text('Move the pin here')),
        ],
      ),
    );
  }
}
