import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'brand_logo.dart';

/// What a plate lookup looks like while it is happening.
///
/// The DVLA and the tyre database are two hops behind us and either can take a
/// few seconds, which is long enough for a stationary button to read as a
/// hung app. So the plate is shown being read: a light passes over the
/// registration, the mark turns, and the caption names the step actually in
/// progress rather than saying "loading".
class PlateScan extends StatefulWidget {
  const PlateScan({required this.plate, super.key});

  final String plate;

  static const _stages = <String>[
    'Reading the plate',
    'Asking the DVLA',
    'Finding your tyre size',
  ];

  @override
  State<PlateScan> createState() => _PlateScanState();
}

class _PlateScanState extends State<PlateScan> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  Timer? _stageTimer;
  int _stage = 0;

  @override
  void initState() {
    super.initState();
    _stageTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (!mounted) return;
      if (_stage < PlateScan._stages.length - 1) setState(() => _stage += 1);
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: <Widget>[
              Container(
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.surfaceSunken,
                  border: Border.all(color: palette.goldDim),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  widget.plate.toUpperCase(),
                  style: palette.plate.copyWith(fontSize: 30, letterSpacing: 5),
                ),
              ),
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (_, __) => FractionallySizedBox(
                    alignment: Alignment(-1 + 2 * _sweep.value, 0),
                    widthFactor: 0.32,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            Color(0x00FFD700),
                            Color(0x33FFD700),
                            Color(0x00FFD700),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        Row(
          children: <Widget>[
            const SpinningMark(size: 26),
            const SizedBox(width: Space.md),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.normal,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
                        .animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  PlateScan._stages[_stage],
                  key: ValueKey<int>(_stage),
                  style: theme.textTheme.titleMedium?.copyWith(color: palette.inkMuted),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.pill),
          child: LinearProgressIndicator(
            minHeight: 4,
            backgroundColor: palette.line,
            valueColor: AlwaysStoppedAnimation<Color>(palette.gold),
            value: null,
          ),
        ),
      ],
    );
  }
}
