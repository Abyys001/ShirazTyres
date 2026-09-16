import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../models/saved_vehicle.dart';
import '../providers/vehicles.dart';
import '../widgets/message_view.dart';
import '../widgets/plate_scan.dart';
import '../widgets/ui_kit.dart';

/// The garage: the cars this customer keeps, and what we know about their tyres.
///
/// A second call-out should not mean typing a registration again, and the tyre
/// size decision from section 4.3 belongs to the car rather than to the job — so
/// it is made once, here, and carried into every call-out afterwards.
class GarageScreen extends ConsumerWidget {
  const GarageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final cars = ref.watch(savedVehiclesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(titleSpacing: Space.xl, title: const Text('Garage')),
      body: RefreshIndicator(
        color: palette.gold,
        backgroundColor: palette.surfaceRaised,
        onRefresh: () => ref.read(savedVehiclesProvider.notifier).refresh(),
        child: cars.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: LoadingBlock(count: 2),
          ),
          error: (error, __) => ListView(
            padding: const EdgeInsets.symmetric(vertical: Space.xxl),
            children: <Widget>[
              MessageView(
                icon: Icons.wifi_tethering_off,
                title: 'We could not open your garage',
                message: '$error',
                onRetry: () => ref.invalidate(savedVehiclesProvider),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? ListView(
                  padding: const EdgeInsets.symmetric(vertical: Space.xxl),
                  children: <Widget>[
                    MessageView(
                      icon: Icons.directions_car_outlined,
                      title: 'No cars yet',
                      message: 'Save one and your next call-out is two taps.',
                      action: FilledButton.icon(
                        onPressed: () => _addCar(context, ref),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Add a car'),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xxxl),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: Space.md),
                  itemBuilder: (context, index) {
                    if (index == list.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: Space.sm),
                        child: OutlinedButton.icon(
                          onPressed: () => _addCar(context, ref),
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('Add another car'),
                        ),
                      );
                    }
                    return _CarCard(
                      car: list[index],
                      onMenu: (action) => _menu(context, ref, list[index], action),
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: cars.valueOrNull == null || cars.valueOrNull!.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/request'),
              backgroundColor: palette.gold,
              foregroundColor: palette.onGold,
              icon: const Icon(Icons.bolt),
              label: Text('Get help now', style: theme.textTheme.labelLarge?.copyWith(
                color: palette.onGold, fontSize: 15)),
            ),
    );
  }

  Future<void> _addCar(BuildContext context, WidgetRef ref) async {
    final palette = context.palette;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.card)),
      ),
      builder: (_) => const _AddCarSheet(),
    );
    if (added == true && context.mounted) Buzz.commit();
  }

  Future<void> _menu(
    BuildContext context,
    WidgetRef ref,
    SavedVehicle car,
    _CarAction action,
  ) async {
    final controller = ref.read(savedVehiclesProvider.notifier);
    try {
      switch (action) {
        case _CarAction.primary:
          await controller.makePrimary(car.id);
        case _CarAction.rename:
          final name = await _askNickname(context, car.nickname);
          if (name != null) await controller.rename(car.id, name);
        case _CarAction.remove:
          await controller.remove(car.id);
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<String?> _askNickname(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this car'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'The Golf'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

enum _CarAction { primary, rename, remove }

/// One car, at the size a car deserves: the plate first, because that is what
/// the owner recognises, then what it is, then the one figure that matters.
class _CarCard extends StatelessWidget {
  const _CarCard({required this.car, required this.onMenu});

  final SavedVehicle car;
  final ValueChanged<_CarAction> onMenu;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return SurfaceCard(
      wash: car.isPrimary,
      accent: car.isPrimary ? palette.gold : null,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PlateBadge(car.plate),
              const Spacer(),
              if (car.isPrimary)
                Padding(
                  padding: EdgeInsets.only(right: Space.xs),
                  child: Icon(Icons.star_rounded, size: 22, color: palette.gold),
                ),
              PopupMenuButton<_CarAction>(
                onSelected: onMenu,
                color: palette.surfaceRaised,
                icon: Icon(Icons.more_horiz, color: palette.inkMuted),
                itemBuilder: (_) => <PopupMenuEntry<_CarAction>>[
                  if (!car.isPrimary)
                    const PopupMenuItem<_CarAction>(
                      value: _CarAction.primary,
                      child: Text('Make this my main car'),
                    ),
                  const PopupMenuItem<_CarAction>(
                    value: _CarAction.rename,
                    child: Text('Rename'),
                  ),
                  const PopupMenuItem<_CarAction>(
                    value: _CarAction.remove,
                    child: Text('Remove'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(car.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: _Fact(
                  icon: Icons.donut_large,
                  label: 'Tyre size',
                  value: car.hasSize ? car.effectiveTyreSize : 'Not known',
                  mono: car.hasSize,
                  tone: car.hasSize ? palette.ink : palette.inkSubtle,
                ),
              ),
              if (car.sizeWasOverridden)
                Tooltip(
                  message: 'You set this size yourself',
                  child: Icon(Icons.edit_note, size: 22, color: palette.warning),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: palette.inkSubtle),
        const SizedBox(width: Space.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: theme.textTheme.bodySmall),
            Text(
              value,
              style: mono
                  ? palette.mono.copyWith(fontSize: 17, fontWeight: FontWeight.w700, color: tone)
                  : theme.textTheme.titleMedium?.copyWith(color: tone),
            ),
          ],
        ),
      ],
    );
  }
}

/// Adding a car is the plate and nothing else. The lookup fills in the rest, and
/// while it runs the registration is visibly being read.
class _AddCarSheet extends ConsumerStatefulWidget {
  const _AddCarSheet();

  @override
  ConsumerState<_AddCarSheet> createState() => _AddCarSheetState();
}

class _AddCarSheetState extends ConsumerState<_AddCarSheet> {
  final _plate = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(savedVehiclesProvider.notifier).add(_plate.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.fieldError('plate') ?? error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.xl,
        Space.xl,
        Space.xl,
        Space.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Add a car', style: theme.textTheme.displaySmall),
          const SizedBox(height: Space.xl),
          AnimatedSize(
            duration: Motion.normal,
            curve: Curves.easeOut,
            child: _busy
                ? PlateScan(plate: _plate.text.trim())
                : TextField(
                    controller: _plate,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    style: palette.plate.copyWith(fontSize: 30, letterSpacing: 5),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9 ]')),
                      LengthLimitingTextInputFormatter(10),
                      TextInputFormatter.withFunction(
                        (_, next) => next.copyWith(text: next.text.toUpperCase()),
                      ),
                    ],
                    decoration: InputDecoration(
                      hintText: 'AB12 CDE',
                      hintStyle: palette.plate.copyWith(
                        fontSize: 30,
                        letterSpacing: 5,
                        color: palette.inkSubtle,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: Space.lg),
                    ),
                    onSubmitted: (_) => _save(),
                  ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: Space.lg),
            InlineNotice(_error!),
          ],
          const SizedBox(height: Space.xl),
          BusyButton(label: 'Look it up', busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
