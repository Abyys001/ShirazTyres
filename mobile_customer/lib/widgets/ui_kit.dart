import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// The pieces every screen in both apps is built from. Keeping them here is what
/// stops each screen inventing its own padding, radius and border.

/// A bordered panel on the raised surface. [accent] paints a hairline in a status
/// colour down the leading edge, which is how a card says "this one is different"
/// without shouting.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.accent,
    this.onTap,
    this.wash = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final VoidCallback? onTap;

  /// Paints the gold gradient behind the card. One per screen, at most.
  final bool wash;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: Radii.cardShape,
        border: Border.all(color: accent?.withValues(alpha: 0.35) ?? palette.line),
        gradient: wash ? palette.wash : null,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: Radii.cardShape,
      child: InkWell(
        borderRadius: Radii.cardShape,
        onTap: () {
          Buzz.tap();
          onTap!();
        },
        child: body,
      ),
    );
  }
}

/// A small-caps eyebrow with an optional trailing action, used to open a section.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {this.trailing, this.step, super.key});

  final String label;
  final Widget? trailing;

  /// Numbered steps in a flow (the request form, driver onboarding).
  final int? step;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        children: <Widget>[
          if (step != null) ...<Widget>[
            _StepDot(step!),
            const SizedBox(width: Space.sm),
          ],
          Expanded(child: Text(label.toUpperCase(), style: palette.eyebrow)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot(this.step);

  final int step;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.goldDim,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: palette.gold.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$step',
        style: TextStyle(
          fontFamily: Fonts.mono,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: palette.gold,
        ),
      ),
    );
  }
}

/// A UK registration, set the way a plate is: mono, wide, on a lozenge.
class PlateBadge extends StatelessWidget {
  const PlateBadge(this.plate, {this.dense = false, super.key});

  final String plate;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (plate.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? Space.sm : Space.md, vertical: dense ? 4 : 7),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.lineStrong),
      ),
      child: Text(plate, style: dense ? palette.plate.copyWith(fontSize: 13, letterSpacing: 1.8) : palette.plate),
    );
  }
}

/// A single figure with its label under it — an ETA, a distance, a total.
class StatBlock extends StatelessWidget {
  const StatBlock({required this.value, required this.label, this.tone, super.key});

  final String value;
  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(color: tone ?? palette.ink),
        ),
        const SizedBox(height: 2),
        Text(label.toUpperCase(), style: palette.eyebrow),
      ],
    );
  }
}

/// What an inline notice is saying, which is what decides its colour. Held as a
/// kind rather than a colour so the tone is resolved against the theme on screen
/// rather than baked into a default argument.
enum _NoticeKind {
  problem,
  warning,
  note;

  Color colour(Palette palette) => switch (this) {
        _NoticeKind.problem => palette.danger,
        _NoticeKind.warning => palette.warning,
        _NoticeKind.note => palette.info,
      };
}

/// Inline feedback that is part of the page, not a snackbar that flies past.
/// [tone] drives the whole treatment, so a warning never has to be styled by hand.
class InlineNotice extends StatelessWidget {
  const InlineNotice(this.message, {this.tone, this.icon, this.action, super.key})
      : _kind = _NoticeKind.problem;

  const InlineNotice.warning(this.message, {this.tone, this.action, super.key})
      : icon = Icons.warning_amber_rounded,
        _kind = _NoticeKind.warning;

  const InlineNotice.info(this.message, {this.tone, this.action, super.key})
      : icon = Icons.info_outline,
        _kind = _NoticeKind.note;

  final String message;

  /// An explicit colour when the caller has one — a status tone, say. Left off,
  /// the notice takes the colour its kind means in the theme on screen.
  final Color? tone;

  final IconData? icon;
  final Widget? action;
  final _NoticeKind _kind;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colour = tone ?? _kind.colour(palette);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: palette.isDark ? 0.10 : 0.08),
        borderRadius: Radii.controlShape,
        border: Border.all(color: colour.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon ?? Icons.error_outline, size: 18, color: colour),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: palette.ink, height: 1.45),
                ),
              ),
            ],
          ),
          if (action != null) ...<Widget>[const SizedBox(height: Space.sm), action!],
        ],
      ),
    );
  }
}

/// A labelled row of facts. Left column is the label, right is the value; the
/// value can be any widget, so a plate badge or a chip drops straight in.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, {this.value = '', this.child, this.mono = false, super.key});

  final String label;
  final String value;
  final Widget? child;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 116,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: child ??
                Text(
                  value.isEmpty ? '—' : value,
                  style: mono
                      ? palette.mono.copyWith(color: palette.ink)
                      : Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15),
                ),
          ),
        ],
      ),
    );
  }
}

/// A button that swaps its label for a spinner while its action is in flight,
/// so a slow network never leaves the screen looking inert.
class BusyButton extends StatelessWidget {
  const BusyButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.outlined = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final child = busy
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: outlined ? palette.gold : palette.onGold,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[Icon(icon, size: 19), const SizedBox(width: Space.sm)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final action = busy || onPressed == null
        ? null
        : () {
            Buzz.tap();
            onPressed!();
          };
    return outlined
        ? OutlinedButton(onPressed: action, child: child)
        : FilledButton(onPressed: action, child: child);
  }
}

/// The full-height "nothing here" state: an icon, a line explaining why, and at
/// most one thing to do about it.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    this.message = '',
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: palette.surface,
              shape: BoxShape.circle,
              border: Border.all(color: palette.line),
            ),
            child: Icon(icon, size: 30, color: palette.inkSubtle),
          ),
          const SizedBox(height: Space.lg),
          Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
          if (message.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.sm),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
          if (action != null) ...<Widget>[const SizedBox(height: Space.xl), action!],
        ],
      ),
    );
  }
}

/// The placeholder a list shows while its first page is in flight. Shaped like
/// the cards that will replace it, so the layout does not jump, and sweeping so
/// it reads as "loading" rather than "broken".
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({this.count = 2, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (var index = 0; index < count; index++)
          const Padding(
            padding: EdgeInsets.only(bottom: Space.md),
            child: Skeleton(height: 108),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Feedback
// ---------------------------------------------------------------------------

/// Haptics, named by what they mean rather than by how hard they buzz. Every
/// control that commits something goes through one of these: at the roadside,
/// in gloves, in the rain, the phone confirming the tap is often the only
/// confirmation that lands.
abstract final class Buzz {
  /// A control was pressed.
  static void tap() => HapticFeedback.selectionClick();

  /// Something irreversible went through.
  static void commit() => HapticFeedback.mediumImpact();

  /// Something arrived that the screen wants looked at.
  static void alert() => HapticFeedback.heavyImpact();
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

/// A sweeping placeholder block. Sized like whatever it stands in for, so the
/// page does not reflow when the real content lands.
class Skeleton extends StatefulWidget {
  const Skeleton({this.height = 16, this.width, this.radius = Radii.card, super.key});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, _) {
        final palette = context.palette;
        final travel = _sweep.value * 2 - 1;
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: palette.line),
            gradient: LinearGradient(
              begin: Alignment(travel - 0.6, 0),
              end: Alignment(travel + 0.6, 0),
              colors: <Color>[palette.surface, palette.surfaceRaised, palette.surface],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Choosing
// ---------------------------------------------------------------------------

/// One option in a grid of them: an icon over a word or two, sized for a thumb
/// rather than a cursor. Picking is a single tap on a large target — no drop-down
/// to open, no list to scroll, no label to read twice.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.caption = '',
    this.tone,
    super.key,
  });

  final String label;
  final String caption;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  /// The colour of being chosen. Gold unless the caller means something else.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null;
    final chosen = tone ?? palette.gold;
    final foreground = !enabled
        ? palette.inkSubtle
        : selected
            ? chosen
            : palette.ink;

    return Material(
      color: selected ? chosen.withValues(alpha: palette.isDark ? 0.12 : 0.10) : palette.surface,
      borderRadius: Radii.cardShape,
      child: InkWell(
        borderRadius: Radii.cardShape,
        onTap: enabled
            ? () {
                Buzz.tap();
                onTap!();
              }
            : null,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.lg),
          constraints: const BoxConstraints(minHeight: 104),
          decoration: BoxDecoration(
            borderRadius: Radii.cardShape,
            border: Border.all(
              color: selected ? chosen : palette.line,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 26, color: selected ? tone : palette.inkMuted),
              const SizedBox(height: Space.md),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: foreground, height: 1.2),
              ),
              if (caption.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// [ChoiceTile]s laid out two to a row. Anything more per row and the labels
/// start wrapping, which is the thing the tiles exist to avoid.
class ChoiceGrid extends StatelessWidget {
  const ChoiceGrid({required this.children, this.columns = 2, super.key});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    const gap = Space.md;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// A row of large radio-style rows for options that need a sentence rather than
/// a word — used where a [ChoiceTile] grid would make the labels wrap.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.caption = '',
    super.key,
  });

  final String label;
  final String caption;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Material(
      color: selected ? palette.goldDim.withValues(alpha: 0.5) : Colors.transparent,
      borderRadius: Radii.controlShape,
      child: InkWell(
        borderRadius: Radii.controlShape,
        onTap: () {
          Buzz.tap();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
          decoration: BoxDecoration(
            borderRadius: Radii.controlShape,
            border: Border.all(color: selected ? palette.gold : Colors.transparent),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 22, color: selected ? palette.gold : palette.inkMuted),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(label, style: theme.textTheme.titleMedium),
                    if (caption.isNotEmpty)
                      Text(caption, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? palette.gold : palette.lineStrong,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Committing
// ---------------------------------------------------------------------------

/// Slide to confirm. Used for anything that cannot be taken back — arriving,
/// finishing, taking payment.
///
/// A tap is one muscle twitch, and a phone in a jacket pocket at the roadside
/// produces plenty of those. A deliberate 60% drag does not happen by accident,
/// which is why every dispatch app worth copying uses this shape for state
/// changes and a plain button for everything else.
class SlideAction extends StatefulWidget {
  const SlideAction({
    required this.label,
    required this.onConfirm,
    this.icon = Icons.chevron_right,
    this.busy = false,
    this.tone,
    super.key,
  });

  final String label;
  final Future<void> Function()? onConfirm;
  final IconData icon;
  final bool busy;
  final Color? tone;

  @override
  State<SlideAction> createState() => _SlideActionState();
}

class _SlideActionState extends State<SlideAction> with SingleTickerProviderStateMixin {
  static const _height = 62.0;
  static const _inset = 5.0;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: Motion.fast,
  )..addListener(() => setState(() => _progress = _settle.value));

  double _progress = 0;
  double _trackWidth = 0;

  double get _travel => math.max(_trackWidth - _height, 1);

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails details) {
    if (widget.onConfirm == null || widget.busy) return;
    setState(() => _progress = (_progress + details.delta.dx / _travel).clamp(0.0, 1.0));
  }

  void _release() {
    if (widget.onConfirm == null || widget.busy) return;
    if (_progress >= 0.6) {
      setState(() => _progress = 1);
      Buzz.commit();
      widget.onConfirm!().whenComplete(() {
        if (mounted) _settleBack();
      });
    } else {
      _settleBack();
    }
  }

  void _settleBack() {
    _settle
      ..value = _progress
      ..animateTo(0, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = widget.onConfirm != null && !widget.busy;
    final tone = enabled ? (widget.tone ?? palette.gold) : palette.lineStrong;

    return LayoutBuilder(
      builder: (context, constraints) {
        final palette = context.palette;
        _trackWidth = constraints.maxWidth;
        final thumbLeft = _inset + _progress * (_trackWidth - _height - _inset);

        return SizedBox(
          height: _height,
          child: Stack(
            children: <Widget>[
              // Track, with the filled part growing behind the thumb.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surfaceSunken,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: Border.all(color: tone.withValues(alpha: 0.35)),
                  ),
                ),
              ),
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _progress.clamp(0.0, 1.0),
                      child: ColoredBox(color: tone.withValues(alpha: 0.18)),
                    ),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: _height),
                  child: Opacity(
                    opacity: (1 - _progress * 1.4).clamp(0.0, 1.0),
                    child: Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: Fonts.sans,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: enabled ? palette.ink : palette.inkSubtle,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: thumbLeft,
                top: _inset,
                child: GestureDetector(
                  onHorizontalDragUpdate: _drag,
                  onHorizontalDragEnd: (_) => _release(),
                  child: Container(
                    width: _height - _inset * 2,
                    height: _height - _inset * 2,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                    ),
                    child: widget.busy
                        ? Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: palette.onGold),
                          )
                        : Icon(widget.icon, color: palette.onGold, size: 24),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The bar that holds a screen's primary action, pinned above the gesture bar.
/// The action stays under the thumb wherever the page is scrolled to, which is
/// the whole reason it is not simply the last thing in the list.
class StickyBar extends StatelessWidget {
  const StickyBar({required this.child, this.secondary, super.key});

  final Widget child;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.canvas,
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            child,
            if (secondary != null) ...<Widget>[const SizedBox(height: Space.sm), secondary!],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wayfinding
// ---------------------------------------------------------------------------

/// One destination in [AppNavBar].
class NavItem {
  const NavItem({required this.icon, required this.activeIcon, required this.label});

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// The persistent bottom bar. Three destinations, always labelled, each a full
/// thumb-sized target — the whole app is reachable without ever hunting for a
/// small icon in a corner.
class AppNavBar extends StatelessWidget {
  const AppNavBar({required this.items, required this.index, required this.onSelect, super.key});

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: <Widget>[
              for (var slot = 0; slot < items.length; slot++)
                Expanded(
                  child: _NavButton(
                    item: items[slot],
                    selected: slot == index,
                    onTap: () {
                      if (slot != index) Buzz.tap();
                      onSelect(slot);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colour = selected ? palette.gold : palette.inkSubtle;
    return InkResponse(
      onTap: onTap,
      radius: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AnimatedContainer(
            duration: Motion.fast,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? palette.goldDim : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Icon(selected ? item.activeIcon : item.icon, size: 23, color: colour),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              fontFamily: Fonts.sans,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

/// A round icon over its label — the phone-call and navigate shortcuts that sit
/// on a job. Reads as one target, and the label never has to be guessed at.
class QuickAction extends StatelessWidget {
  const QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tone,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null;
    final colour = enabled ? tone : palette.inkSubtle;
    return InkWell(
      borderRadius: Radii.cardShape,
      onTap: enabled
          ? () {
              Buzz.tap();
              onTap!();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                shape: BoxShape.circle,
                border: Border.all(color: palette.line),
              ),
              child: Icon(icon, size: 22, color: colour),
            ),
            const SizedBox(height: Space.sm),
            Text(
              label,
              style: TextStyle(
                fontFamily: Fonts.sans,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colour,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detail that is worth keeping but not worth reading every time. Collapsed by
/// default: the screen shows the answer, and the working is one tap away.
class ExpandableCard extends StatefulWidget {
  const ExpandableCard({
    required this.title,
    required this.child,
    this.icon = Icons.notes_outlined,
    this.initiallyOpen = false,
    super.key,
  });

  final String title;
  final Widget child;
  final IconData icon;
  final bool initiallyOpen;

  @override
  State<ExpandableCard> createState() => _ExpandableCardState();
}

class _ExpandableCardState extends State<ExpandableCard> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () {
              Buzz.tap();
              setState(() => _open = !_open);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              child: Row(
                children: <Widget>[
                  Icon(widget.icon, size: 20, color: palette.inkSubtle),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: Motion.fast,
                    child: Icon(Icons.expand_more, size: 22, color: palette.inkSubtle),
                  ),
                ],
              ),
            ),
          ),
          // The detail is not built while it is closed: a crossfade would keep
          // it in the tree, which costs a rebuild nobody sees and leaves a
          // screen reader announcing a section that is not open.
          AnimatedSize(
            duration: Motion.normal,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(bottom: Space.lg),
                    child: widget.child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Progress through a numbered flow, as one filled segment per step. Says how
/// much is left without spending a line of prose on it.
class StepBar extends StatelessWidget {
  const StepBar({required this.step, required this.total, this.label = '', super.key});

  final int step;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (var slot = 0; slot < total; slot++) ...<Widget>[
              if (slot > 0) const SizedBox(width: 5),
              Expanded(
                child: AnimatedContainer(
                  duration: Motion.normal,
                  height: 4,
                  decoration: BoxDecoration(
                    color: slot < step ? palette.gold : palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (label.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.sm),
          Text('STEP $step OF $total · ${label.toUpperCase()}', style: palette.eyebrow),
        ],
      ],
    );
  }
}

/// The one number a screen exists to show — an ETA, a total — set as large as it
/// will go with its unit tucked against the baseline.
class HeroFigure extends StatelessWidget {
  const HeroFigure({
    required this.value,
    required this.unit,
    this.caption = '',
    this.tone,
    super.key,
  });

  final String value;
  final String unit;
  final String caption;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(value, style: theme.textTheme.displayLarge?.copyWith(color: tone)),
            const SizedBox(width: Space.sm),
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(unit, style: theme.textTheme.titleLarge),
            ),
          ],
        ),
        if (caption.isNotEmpty) Text(caption, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// A horizontal rail of the states a job passes through, with the current one
/// lit. Replaces a timestamped list for the "where are we up to" question — the
/// shape answers it before any of the words are read.
class ProgressRail extends StatelessWidget {
  const ProgressRail({required this.stages, required this.reached, this.tone, super.key});

  /// Short labels, in order.
  final List<String> stages;

  /// How many are behind us, 0..stages.length.
  final int reached;

  /// The colour of the part that is done. Gold unless the caller means a status.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lit = tone ?? palette.gold;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var slot = 0; slot < stages.length; slot++)
          Expanded(
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Container(
                        height: 2,
                        color: slot == 0
                            ? Colors.transparent
                            : slot < reached
                                ? lit
                                : palette.line,
                      ),
                    ),
                    AnimatedContainer(
                      duration: Motion.normal,
                      width: slot == reached - 1 ? 14 : 10,
                      height: slot == reached - 1 ? 14 : 10,
                      decoration: BoxDecoration(
                        color: slot < reached ? lit : palette.surfaceRaised,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: slot < reached ? lit : palette.lineStrong,
                          width: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: slot == stages.length - 1
                            ? Colors.transparent
                            : slot < reached - 1
                                ? lit
                                : palette.line,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Text(
                  stages[slot],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: Fonts.sans,
                    fontSize: 10.5,
                    fontWeight: slot == reached - 1 ? FontWeight.w700 : FontWeight.w500,
                    color: slot < reached ? palette.ink : palette.inkSubtle,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
