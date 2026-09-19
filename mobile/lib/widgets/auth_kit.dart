import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import 'theme_switch.dart';
import 'brand_logo.dart';
import 'ui_kit.dart';

/// The pieces the two sign-in flows are built from.
///
/// A sign-in screen has one job and about eleven words to do it in. Everything
/// here exists so those words do not have to be a paragraph: the backdrop says
/// "premium", the hero says who we are, the beat strip says what happens next in
/// pictures, and the code field shows progress instead of describing it.

/// A slow gold light behind the page. Nothing moves fast enough to notice while
/// typing; it is only there so the screen is not a flat rectangle.
class AuthBackdrop extends StatefulWidget {
  const AuthBackdrop({required this.child, super.key});

  final Widget child;

  @override
  State<AuthBackdrop> createState() => _AuthBackdropState();
}

class _AuthBackdropState extends State<AuthBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ColoredBox(
      color: palette.canvas,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (_, __) => CustomPaint(painter: _GlowPainter(_drift.value, context.palette)),
            ),
          ),
          Positioned.fill(child: widget.child),

          // Appearance before there is an account to hang it on. Somebody
          // signing in at night should not have to finish signing in before
          // they can turn the screen down.
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: const ThemeToggleButton(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter(this.t, this.palette);

  final double t;

  /// A painter sits outside the widget tree, so the palette is handed to it
  /// rather than looked up — and repainting when it changes is why it is part
  /// of [shouldRepaint].
  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset centre, double radius, Color colour) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(centre, radius, <Color>[colour, palette.canvas.withValues(alpha: 0)])
          ..blendMode = BlendMode.plus,
      );
    }

    blob(
      Offset(size.width * (0.18 + 0.12 * t), size.height * (0.10 + 0.04 * t)),
      size.width * 0.85,
      palette.gold.withValues(alpha: 0.11),
    );
    blob(
      Offset(size.width * (0.92 - 0.10 * t), size.height * (0.72 - 0.06 * t)),
      size.width * 0.70,
      palette.accent.withValues(alpha: 0.13),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.t != t || old.palette != palette;
}

/// The body of a sign-in screen: centred when the content is shorter than the
/// screen, and scrolling when it is not.
///
/// Both flows are short enough to leave the bottom third of a tall phone empty,
/// which reads as a page that failed to finish loading rather than as one with
/// room to breathe.
class AuthLayout extends StatelessWidget {
  const AuthLayout({required this.children, super.key});

  final List<Widget> children;

  static const _insets = EdgeInsets.fromLTRB(Space.xl, Space.xxl, Space.xl, Space.xl);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: _insets,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, constraints.maxHeight - _insets.vertical),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo, name, and at most one short line, so the screen they land on is
/// visibly the same brand as the tile they tapped.
class AuthHero extends StatelessWidget {
  const AuthHero({required this.title, this.kicker = '', super.key});

  final String title;
  final String kicker;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const BrandLogo(height: 76),
        const SizedBox(height: Space.xl),
        Text(title, style: theme.textTheme.displayMedium),
        if (kicker.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.xs),
          Text(kicker, style: theme.textTheme.titleMedium?.copyWith(color: palette.inkMuted)),
        ],
      ],
    );
  }
}

/// One picture and one or two words. Three of these replace the paragraph that
/// used to explain the service, and they arrive one after another so the strip
/// reads like a sentence being spoken rather than a line of static icons.
class BeatStrip extends StatefulWidget {
  const BeatStrip({required this.beats, super.key});

  final List<(IconData, String)> beats;

  @override
  State<BeatStrip> createState() => _BeatStripState();
}

class _BeatStripState extends State<BeatStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 320 + 180 * widget.beats.length),
  )..forward();

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final count = widget.beats.length;

    return AnimatedBuilder(
      animation: _in,
      builder: (_, __) => Row(
        children: <Widget>[
          for (var i = 0; i < count; i++) ...<Widget>[
            if (i > 0)
              Expanded(
                child: _Thread(progress: _slot(i - 0.5)),
              ),
            Opacity(
              opacity: _slot(i.toDouble()),
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - _slot(i.toDouble()))),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.surfaceRaised,
                        border: Border.all(color: palette.goldDim),
                      ),
                      child: Icon(widget.beats[i].$1, size: 21, color: palette.gold),
                    ),
                    const SizedBox(height: Space.sm),
                    Text(widget.beats[i].$2, style: theme.textTheme.labelLarge),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Staggered: each beat gets its own slice of the run.
  double _slot(double index) {
    final start = index / (widget.beats.length + 0.5);
    return ((_in.value - start) / 0.4).clamp(0.0, 1.0);
  }
}

class _Thread extends StatelessWidget {
  const _Thread({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: CustomPaint(size: const Size(double.infinity, 2), painter: _ThreadPainter(progress, context.palette)),
      );
}

class _ThreadPainter extends CustomPainter {
  const _ThreadPainter(this.progress, this.palette);

  final double progress;
  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = palette.goldDim
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 5.0;
    for (var x = 2.0; x < size.width * progress; x += dash * 2) {
      canvas.drawLine(Offset(x, 1), Offset(math.min(x + dash, size.width * progress), 1), paint);
    }
  }

  @override
  bool shouldRepaint(_ThreadPainter old) => old.progress != progress || old.palette != palette;
}

/// A six-cell code entry. The cells are the progress bar: there is nothing to
/// read, and a filled cell is visible from arm's length in daylight.
class CodeField extends StatefulWidget {
  const CodeField({
    required this.controller,
    required this.focusNode,
    this.length = 6,
    this.onCompleted,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final VoidCallback? onCompleted;
  final bool enabled;

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    if (widget.controller.text.length == widget.length) {
      Buzz.commit();
      widget.onCompleted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = widget.controller.text;
    final focused = widget.focusNode.hasFocus;

    return Stack(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (var i = 0; i < widget.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: Space.sm),
              Expanded(child: _Cell(
                digit: i < digits.length ? digits[i] : '',
                active: focused && i == digits.length,
              )),
            ],
          ],
        ),
        // The real field, invisible and on top: the platform keyboard and SMS
        // autofill both need something they recognise.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              autofillHints: const <String>[AutofillHints.oneTimeCode],
              showCursor: false,
              enableInteractiveSelection: false,
              style: const TextStyle(color: Colors.transparent),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length),
              ],
              decoration: const InputDecoration(counterText: ''),
              onTap: () => widget.controller.selection =
                  TextSelection.collapsed(offset: widget.controller.text.length),
            ),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.digit, required this.active});

  final String digit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final filled = digit.isNotEmpty;
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Curves.easeOut,
      height: 62,
      decoration: BoxDecoration(
        color: filled ? palette.surfaceRaised : palette.surfaceSunken,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? palette.gold : (filled ? palette.lineStrong : palette.line),
          width: active ? 2 : 1,
        ),
        boxShadow: active
            ? <BoxShadow>[BoxShadow(color: palette.gold.withValues(alpha: 0.25), blurRadius: 14)]
            : null,
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: Motion.fast,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: filled
            ? Text(
                digit,
                key: ValueKey<String>('$digit${digit.hashCode}'),
                style: palette.mono.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              )
            : Container(
                key: const ValueKey<String>('empty'),
                width: 8,
                height: 2,
                color: palette.lineStrong,
              ),
      ),
    );
  }
}

/// Cross-fades between the two halves of a sign-in: number, then code. The slide
/// is small and sideways, so it reads as one screen advancing rather than two
/// screens swapping.
class StepSwap extends StatelessWidget {
  const StepSwap({required this.stepKey, required this.child, super.key});

  final Object stepKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Motion.normal,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero)
                .animate(animation),
            child: child,
          ),
        ),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[...previous, if (current != null) current],
        ),
        child: KeyedSubtree(key: ValueKey<Object>(stepKey), child: child),
      );
}

/// The resend timer as a ring that empties, with the seconds inside it. Replaces
/// "Send another code in 42s" with something that can be glanced at.
class ResendRing extends StatelessWidget {
  const ResendRing({required this.secondsLeft, required this.total, required this.onResend, super.key});

  final int secondsLeft;
  final int total;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (secondsLeft <= 0) {
      return TextButton.icon(
        onPressed: onResend,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Send another code'),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 30,
          height: 30,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 1, end: total == 0 ? 0 : secondsLeft / total),
                duration: const Duration(milliseconds: 900),
                builder: (_, value, __) => CircularProgressIndicator(
                  value: value,
                  strokeWidth: 2.5,
                  backgroundColor: palette.line,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.gold),
                ),
              ),
              Text('$secondsLeft', style: palette.mono.copyWith(fontSize: 11, color: palette.inkMuted)),
            ],
          ),
        ),
        const SizedBox(width: Space.md),
        Text('Another code', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
