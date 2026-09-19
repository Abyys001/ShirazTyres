import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/settings.dart';
import 'ui_kit.dart';

/// The light/dark control, in the two shapes the apps need it.
///
/// Appearance is a setting somebody changes once and forgets, so the full
/// control lives on the account screen — three named options rather than a
/// switch, because "follow my phone" is a real answer and a two-state switch
/// cannot say it. The auth screens get [ThemeToggleButton] instead: one tap,
/// no labels, because at that point there is nothing to set up yet and somebody
/// squinting at a white screen at night wants it gone, not explained.

/// Three options on a sliding track. The chosen one carries the gold.
class ThemeChoice extends ConsumerWidget {
  const ThemeChoice({super.key});

  static const _options = <(ThemeMode, IconData, String)>[
    (ThemeMode.light, Icons.light_mode_outlined, 'Light'),
    (ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
    (ThemeMode.system, Icons.brightness_auto_outlined, 'Auto'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final mode = ref.watch(themeModeProvider);
    final index = _options.indexWhere((option) => option.$1 == mode);

    // The track is sized in text, not in pixels. At the larger accessibility
    // scales a fixed 50px box clipped the labels it exists to show, and three
    // unshrinkable rows of icon-plus-word overflowed the width — which is what
    // put a stripe of overflow warning across this one row and nowhere else.
    final scale = MediaQuery.textScalerOf(context);
    final height = scale.scale(14) * 2.4 + 12;

    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = (constraints.maxWidth - 8) / _options.length;
        return Container(
          height: height.clamp(50.0, 88.0),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: palette.surfaceSunken,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: palette.line),
          ),
          child: Stack(
            children: <Widget>[
              // The indicator slides rather than blinks, so the eye follows the
              // choice across instead of hunting for where it went. It carries
              // no shadow: inside a 4px track a lifted pill reads as a pill that
              // has come loose.
              AnimatedPositioned(
                duration: Motion.normal,
                curve: Curves.easeOutCubic,
                left: slot * (index < 0 ? 2 : index),
                width: slot,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.goldFill,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (final (option, icon, label) in _options)
                    Expanded(
                      child: _Segment(
                        icon: icon,
                        label: label,
                        // Below the width its own label needs, a segment keeps
                        // the icon and drops the word rather than truncating it
                        // to a letter and an ellipsis.
                        showLabel: slot >= scale.scale(14) * 3.4 + 34,
                        selected: option == mode,
                        onTap: () {
                          Buzz.tap();
                          ref.read(themeModeProvider.notifier).set(option);
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showLabel = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// False when the track is too narrow for the word. The icon still says which
  /// option this is, and the tooltip says it in full for anyone who needs it.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colour = selected ? palette.onGold : palette.inkMuted;

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(icon, size: 17, color: colour),
        if (showLabel) ...<Widget>[
          const SizedBox(width: 6),
          // Flexible, because the width this sits in is a third of whatever the
          // screen gives us and the word is whatever the system's text scale
          // makes of it. An ellipsis is a poor label; an overflow is not a
          // label at all.
          Flexible(
            child: AnimatedDefaultTextStyle(
              duration: Motion.fast,
              style: TextStyle(
                fontFamily: Fonts.sans,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: colour,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ],
    );

    return InkWell(
      borderRadius: BorderRadius.circular(Radii.pill),
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: showLabel ? content : Tooltip(message: label, child: content),
      ),
    );
  }
}

/// One tap, on screens with no room for a setting: it goes to the opposite of
/// what is on screen. Follows the system until somebody touches it, and the
/// glyph is the brightness being offered, not the one already showing — a sun
/// on a dark screen means "make it light".
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({this.tooltip = true, super.key});

  final bool tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final dark = palette.isDark;

    final button = IconButton(
      onPressed: () {
        Buzz.tap();
        ref.read(themeModeProvider.notifier).toggle(palette.brightness);
      },
      style: IconButton.styleFrom(
        backgroundColor: palette.surfaceSunken,
        foregroundColor: palette.gold,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
          side: BorderSide(color: palette.line),
        ),
        minimumSize: const Size.square(44),
      ),
      icon: AnimatedSwitcher(
        duration: Motion.normal,
        transitionBuilder: (child, animation) => RotationTransition(
          turns: Tween<double>(begin: 0.75, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          key: ValueKey<bool>(dark),
          size: 20,
        ),
      ),
    );

    if (!tooltip) return button;
    return Tooltip(message: dark ? 'Switch to light' : 'Switch to dark', child: button);
  }
}
