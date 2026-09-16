import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The drawn mark: an S cut through a tyre.
///
/// Eighteen tread blocks around the rim and a single continuous groove through
/// the middle. It is one symbol and one colour on a plain ground, which is what
/// survives being 48 pixels wide on a home screen — and the tread is a ring the
/// moment it is too small to count, so it never turns to mush.
///
/// [spin] turns the tread without moving the groove, which is the whole loading
/// animation: the wheel is running, the letter is not. Identity is [BrandLogo]'s
/// job — this is only what the app shows while it waits.
class ShirazMark extends StatelessWidget {
  const ShirazMark({
    required this.size,
    this.mark,
    this.field = Colors.transparent,
    this.spin = 0,
    super.key,
  });

  final double size;

  /// Defaults to the identity gold, which does not change with the theme.
  final Color? mark;
  final Color field;
  final double spin;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(mark: mark ?? context.palette.goldFill, field: field, spin: spin),
      );
}

/// The same mark with its tread turning. Used wherever the app is waiting on
/// something it cannot hurry — a plate lookup, a cold start, a dispatch.
class SpinningMark extends StatefulWidget {
  const SpinningMark({
    required this.size,
    this.mark,
    this.field = Colors.transparent,
    this.running = true,
    super.key,
  });

  final double size;
  final Color? mark;
  final Color field;
  final bool running;

  @override
  State<SpinningMark> createState() => _SpinningMarkState();
}

class _SpinningMarkState extends State<SpinningMark> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.running) _controller.repeat();
  }

  @override
  void didUpdateWidget(SpinningMark old) {
    super.didUpdateWidget(old);
    if (widget.running == old.running) return;
    widget.running ? _controller.repeat() : _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => ShirazMark(
          size: widget.size,
          mark: widget.mark,
          field: widget.field,
          spin: _controller.value * 2 * math.pi,
        ),
      );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.mark, required this.field, required this.spin});

  final Color mark;
  final Color field;
  final double spin;

  /// Drawn in a 100-unit square and scaled, so every ratio below is readable as
  /// a percentage of the mark.
  static const _blocks = 18;
  static const _treadRadius = 43.0;
  static const _treadWidth = 9.5;
  static const _grooveWidth = 12.5;

  /// The groove is drawn full size and pulled in, so it clears the tread.
  static const _grooveScale = 0.84;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 100;
    canvas.save();
    canvas.scale(scale);

    if (field.a > 0) {
      canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = field);
    }

    final ink = Paint()
      ..color = mark
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    const rim = Rect.fromLTRB(
      50 - _treadRadius, 50 - _treadRadius, 50 + _treadRadius, 50 + _treadRadius,
    );
    const step = 2 * math.pi / _blocks;
    ink.strokeWidth = _treadWidth;
    ink.strokeCap = StrokeCap.butt;
    for (var i = 0; i < _blocks; i++) {
      canvas.drawArc(rim, spin + i * step, step * 0.58, false, ink);
    }

    ink
      ..strokeWidth = _grooveWidth / _grooveScale
      ..strokeCap = StrokeCap.round;
    canvas
      ..translate(50, 50)
      ..scale(_grooveScale)
      ..translate(-50, -50)
      ..drawPath(_groove, ink);

    canvas.restore();
  }

  /// One stroke, drawn the way a finger would draw it: the spine of an S that
  /// also reads as the groove between two blocks of tread.
  static final Path _groove = Path()
    ..moveTo(68, 33)
    ..cubicTo(66, 24, 52, 21, 43, 26)
    ..cubicTo(32, 32, 32, 44, 44, 49)
    ..cubicTo(57, 55, 69, 57, 68, 68)
    ..cubicTo(67, 79, 51, 82, 38, 76);

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.mark != mark || old.field != field || old.spin != spin;
}

/// The ShirazTyres logo, as artwork rather than geometry.
///
/// Two files, not one tinted asset: the mark is navy and gold, and navy on the
/// technician app's ink canvas is a hole. The variant follows the theme, so the
/// technician build gets the light-on-dark treatment and the customer build the
/// original, without either caller having to know which it is.
class BrandLogo extends StatelessWidget {
  const BrandLogo({required this.height, super.key});

  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
        context.palette.isDark ? 'assets/brand/logo-dark.png' : 'assets/brand/logo.png',
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'ShirazTyres',
      );
}
