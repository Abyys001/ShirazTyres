import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/damaged_tyre.dart';

/// The damaged wheels, drawn and listed — read-only.
///
/// The technician loads the van from this, so it is the same diagram the
/// customer tapped rather than a second rendering of the same idea: a drawing
/// that disagrees with the one the customer used is worse than no drawing.
class TyreDamageView extends StatelessWidget {
  const TyreDamageView({required this.damaged, super.key});

  final List<DamagedTyre> damaged;

  static const _corners = <TyrePosition, Offset>{
    TyrePosition.frontLeft: Offset(0.175, 0.265),
    TyrePosition.frontRight: Offset(0.825, 0.265),
    TyrePosition.rearLeft: Offset(0.175, 0.735),
    TyrePosition.rearRight: Offset(0.825, 0.735),
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (damaged.isEmpty) {
      return Text(
        'The customer did not say which wheel — ask when you arrive.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final hit = damaged.map((tyre) => tyre.position).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (hit.any(_corners.containsKey))
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 210, maxHeight: 270),
              child: AspectRatio(
                aspectRatio: 0.78,
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      CustomPaint(painter: _CarPainter(palette)),
                      for (final entry in _corners.entries)
                        if (hit.contains(entry.key))
                          Positioned(
                            left: constraints.maxWidth * entry.value.dx - 21,
                            top: constraints.maxHeight * entry.value.dy - 21,
                            width: 42,
                            height: 42,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: palette.danger.withValues(alpha: 0.22),
                                border: Border.all(color: palette.danger, width: 2.5),
                              ),
                              child: Icon(Icons.priority_high, size: 20, color: palette.danger),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: Space.md),
        TyreDamageList(damaged: damaged),
      ],
    );
  }
}

/// A car from above, in the palette, with four wheels where the targets are.
///
/// Drawn rather than an asset: it has to work on both themes, and the wheel
/// positions have to stay in step with `_WheelTarget._offsets`, which a picture
/// cannot guarantee.
class _CarPainter extends CustomPainter {
  const _CarPainter(this.palette);

  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final bodyRect = RRect.fromLTRBAndCorners(
      width * 0.26,
      height * 0.045,
      width * 0.74,
      height * 0.955,
      topLeft: Radius.circular(width * 0.16),
      topRight: Radius.circular(width * 0.16),
      bottomLeft: Radius.circular(width * 0.10),
      bottomRight: Radius.circular(width * 0.10),
    );

    canvas.drawRRect(
      bodyRect,
      Paint()
        ..style = PaintingStyle.fill
        ..color = palette.surfaceRaised,
    );
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = palette.lineStrong,
    );

    // Windscreen and rear screen: enough to tell which end is the front.
    final glass = Paint()..color = palette.surfaceSunken;
    canvas.drawRRect(
      RRect.fromLTRBR(
        width * 0.31,
        height * 0.13,
        width * 0.69,
        height * 0.27,
        Radius.circular(width * 0.05),
      ),
      glass,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        width * 0.31,
        height * 0.72,
        width * 0.69,
        height * 0.85,
        Radius.circular(width * 0.045),
      ),
      glass,
    );

    // Roof line, so the middle does not read as empty.
    canvas.drawLine(
      Offset(width * 0.5, height * 0.30),
      Offset(width * 0.5, height * 0.69),
      Paint()
        ..strokeWidth = 1
        ..color = palette.line,
    );

    // The four wheels, at the fractions `_WheelTarget` positions its targets on.
    final tyre = Paint()..color = palette.lineStrong;
    for (final centre in const <Offset>[
      Offset(0.175, 0.265),
      Offset(0.825, 0.265),
      Offset(0.175, 0.735),
      Offset(0.825, 0.735),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(width * centre.dx, height * centre.dy),
            width: width * 0.13,
            height: height * 0.145,
          ),
          Radius.circular(width * 0.03),
        ),
        tyre,
      );
    }

    // Which side is which, in the words the trade uses.
    _sideLabel(canvas, 'NEARSIDE', Offset(width * 0.175, height * 0.50), size);
    _sideLabel(canvas, 'OFFSIDE', Offset(width * 0.825, height * 0.50), size);
    _sideLabel(canvas, 'FRONT', Offset(width * 0.5, height * 0.015), size, top: true);
  }

  void _sideLabel(Canvas canvas, String text, Offset centre, Size size, {bool top = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: Fonts.sans,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: palette.inkSubtle,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    if (!top) canvas.rotate(centre.dx < size.width / 2 ? -1.5708 : 1.5708);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CarPainter oldDelegate) => oldDelegate.palette != palette;
}

/// The damaged wheels in words, under the diagram.
class TyreDamageList extends StatelessWidget {
  const TyreDamageList({required this.damaged, super.key});

  final List<DamagedTyre> damaged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (damaged.isEmpty) {
      return Text(
        'The customer did not say which wheel.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final tyre in damaged)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.trip_origin, size: 18, color: palette.danger),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        tyre.severity == null
                            ? tyre.position.label
                            : '${tyre.position.label} — ${tyre.severity!.label.toLowerCase()}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (tyre.note.isNotEmpty)
                        Text(tyre.note, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
