import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/damaged_tyre.dart';

export '../models/damaged_tyre.dart';

/// Pick the damaged wheels off a drawing of the car.
///
/// Asking "which tyre?" in a text field produced answers like "the front one"
/// and "driver's side", which is not enough to load a van — the technician found
/// out on arrival, and the wrong tyre meant a second call-out. A picture removes
/// the vocabulary problem entirely: the customer is standing next to the car and
/// points at the wheel.
///
/// The car is drawn rather than shipped as an asset so it takes the palette and
/// works in both themes, and so the selected state is a property of the paint
/// rather than a second image. Nearside and offside are both labelled, because
/// the trade words are the ones the technician needs and nobody stranded on a
/// hard shoulder knows them.
class TyrePicker extends StatelessWidget {
  const TyrePicker({required this.selected, required this.onChanged, super.key});

  final List<DamagedTyre> selected;
  final ValueChanged<List<DamagedTyre>> onChanged;

  bool _isSelected(TyrePosition position) =>
      selected.any((tyre) => tyre.position == position);

  void _toggle(TyrePosition position) {
    final next = List<DamagedTyre>.from(selected);
    final index = next.indexWhere((tyre) => tyre.position == position);
    if (index >= 0) {
      next.removeAt(index);
    } else {
      next.add(DamagedTyre(position: position));
    }
    onChanged(next);
  }

  void _setSeverity(TyrePosition position, TyreSeverity? severity) {
    final next = [
      for (final tyre in selected)
        if (tyre.position == position)
          tyre.copyWith(severity: severity, clearSeverity: severity == null)
        else
          tyre,
    ];
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300, maxHeight: 380),
            child: AspectRatio(
              aspectRatio: 0.78,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      CustomPaint(painter: _CarPainter(palette)),
                      for (final position in _cornerPositions)
                        _WheelTarget(
                          position: position,
                          size: constraints.biggest,
                          selected: _isSelected(position),
                          onTap: () => _toggle(position),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),

        const SizedBox(height: Space.md),
        Center(
          child: Text(
            'Tap the wheel that has gone. Tap it again to undo.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: Space.lg),
        // The spare has no place on the plan view — it is not at a corner — so
        // it gets its own row rather than a pin floating in the boot.
        _SpareRow(
          selected: _isSelected(TyrePosition.spare),
          onTap: () => _toggle(TyrePosition.spare),
        ),

        if (selected.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.xl),
          Text('HOW BAD IS IT?', style: palette.eyebrow),
          const SizedBox(height: Space.sm),
          for (final tyre in _ordered(selected))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: _SeverityRow(
                tyre: tyre,
                onSeverity: (severity) => _setSeverity(tyre.position, severity),
              ),
            ),
        ],
      ],
    );
  }

  /// Always front to back, whatever order they were tapped in.
  static List<DamagedTyre> _ordered(List<DamagedTyre> tyres) {
    final sorted = List<DamagedTyre>.from(tyres);
    sorted.sort((a, b) =>
        TyrePosition.values.indexOf(a.position).compareTo(TyrePosition.values.indexOf(b.position)));
    return sorted;
  }

  static const _cornerPositions = <TyrePosition>[
    TyrePosition.frontLeft,
    TyrePosition.frontRight,
    TyrePosition.rearLeft,
    TyrePosition.rearRight,
  ];
}

/// The tap target over one corner wheel, and the ring that shows its state.
class _WheelTarget extends StatelessWidget {
  const _WheelTarget({
    required this.position,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final TyrePosition position;
  final Size size;
  final bool selected;
  final VoidCallback onTap;

  /// Fractions of the box, matched to where `_CarPainter` puts the wheels.
  static const _offsets = <TyrePosition, Offset>{
    TyrePosition.frontLeft: Offset(0.175, 0.265),
    TyrePosition.frontRight: Offset(0.825, 0.265),
    TyrePosition.rearLeft: Offset(0.175, 0.735),
    TyrePosition.rearRight: Offset(0.825, 0.735),
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final offset = _offsets[position]!;
    const target = 62.0;

    return Positioned(
      left: size.width * offset.dx - target / 2,
      top: size.height * offset.dy - target / 2,
      width: target,
      height: target,
      child: Semantics(
        button: true,
        selected: selected,
        label: '${position.plain} tyre, ${position.label}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? palette.danger.withValues(alpha: 0.18) : Colors.transparent,
              border: Border.all(
                color: selected ? palette.danger : palette.lineStrong,
                width: selected ? 3 : 1.5,
              ),
            ),
            child: Center(
              child: AnimatedScale(
                duration: Motion.fast,
                scale: selected ? 1 : 0,
                child: Icon(Icons.priority_high, size: 26, color: palette.danger),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpareRow extends StatelessWidget {
  const _SpareRow({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: Radii.cardShape,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: selected ? palette.danger.withValues(alpha: 0.10) : palette.surface,
          borderRadius: Radii.cardShape,
          border: Border.all(color: selected ? palette.danger : palette.line),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 22,
              color: selected ? palette.danger : palette.inkSubtle,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('The spare', style: Theme.of(context).textTheme.bodyLarge),
                  Text(
                    'Already fitted and now flat, or flat in the boot.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How bad one selected wheel is. Optional — a customer who does not know can
/// leave it, and the technician still knows which wheel to bring a tyre for.
class _SeverityRow extends StatelessWidget {
  const _SeverityRow({required this.tyre, required this.onSeverity});

  final DamagedTyre tyre;
  final ValueChanged<TyreSeverity?> onSeverity;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: Radii.cardShape,
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.trip_origin, size: 18, color: palette.danger),
              const SizedBox(width: Space.sm),
              Text(tyre.position.plain, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(width: Space.sm),
              Text(
                '(${tyre.position.label})',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: <Widget>[
              for (final severity in TyreSeverity.values)
                ChoiceChip(
                  label: Text(severity.label),
                  selected: tyre.severity == severity,
                  onSelected: (chosen) => onSeverity(chosen ? severity : null),
                ),
            ],
          ),
        ],
      ),
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

/// The same diagram, read-only, for the technician and anybody reviewing a job.
class TyreDiagramSummary extends StatelessWidget {
  const TyreDiagramSummary({required this.damaged, super.key});

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
