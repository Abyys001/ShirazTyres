import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/driver.dart';
import '../models/vehicle.dart';
import '../providers/auth.dart';
import '../providers/vehicles.dart';
import '../widgets/ui_kit.dart';

/// The two vehicle questions a technician has, on one screen.
///
/// Above: any registration, answered — what the car is and what tyre it takes,
/// which is what decides whether the van already has the stock to finish the
/// job. Below: their own vehicle, and the dates that stop them working if they
/// pass unnoticed.
class VehicleScreen extends ConsumerStatefulWidget {
  const VehicleScreen({super.key});

  @override
  ConsumerState<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends ConsumerState<VehicleScreen> {
  final _plate = TextEditingController();

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  void _lookUp() {
    final plate = _plate.text.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
    if (plate.length < 2) return;
    Buzz.tap();
    FocusScope.of(context).unfocus();
    ref.invalidate(plateLookupProvider(plate));
    ref.read(plateQueryProvider.notifier).state = plate;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final query = ref.watch(plateQueryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicles')),
      body: RefreshIndicator(
        color: palette.gold,
        backgroundColor: palette.surfaceRaised,
        onRefresh: () => ref.read(myVehiclesProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxxl),
          children: <Widget>[
            const SectionHeader('Plate lookup'),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _plate,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    textInputAction: TextInputAction.search,
                    style: palette.plate.copyWith(fontSize: 26, letterSpacing: 4),
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
                        fontSize: 26,
                        letterSpacing: 4,
                        color: palette.inkSubtle,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: Space.lg),
                    ),
                    onSubmitted: (_) => _lookUp(),
                  ),
                  const SizedBox(height: Space.lg),
                  FilledButton.icon(
                    onPressed: _lookUp,
                    icon: const Icon(Icons.search, size: 20),
                    label: const Text('Look it up'),
                  ),
                ],
              ),
            ),
            if (query.isNotEmpty) ...<Widget>[
              const SizedBox(height: Space.md),
              _LookupResult(plate: query),
            ],
            const SizedBox(height: Space.xxl),
            const _MyCar(),
          ],
        ),
      ),
    );
  }
}

/// What came back for one registration. A miss is a plain sentence, not a
/// failure: DVLA not knowing a plate is an ordinary answer at a roadside.
class _LookupResult extends ConsumerWidget {
  const _LookupResult({required this.plate});

  final String plate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return ref.watch(plateLookupProvider(plate)).when(
          loading: () => const LoadingBlock(count: 1),
          error: (error, __) => InlineNotice(
            error is ApiException ? error.message : '$error',
            action: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => ref.invalidate(plateLookupProvider(plate)),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
            ),
          ),
          data: (vehicle) => SurfaceCard(
            accent: palette.gold,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    PlateBadge(vehicle.label),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        vehicle.title.isEmpty ? 'Unknown vehicle' : vehicle.title,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),

                // The tyre first: it is the only line on this card that decides
                // whether the van already has what the job needs.
                _TyreSpec(vehicle: vehicle),

                const SizedBox(height: Space.md),
                DetailRow('Colour', value: vehicle.colour),
                DetailRow('Fuel', value: vehicle.fuelType),
                DetailRow(
                  'Engine',
                  value: vehicle.engineCapacity == null ? '' : '${vehicle.engineCapacity} cc',
                ),
                DetailRow('Year', value: vehicle.year == null ? '' : '${vehicle.year}'),
                _LegalRow(
                  label: 'MOT',
                  status: vehicle.motStatus,
                  date: vehicle.motExpiryDate,
                  dateLabel: 'expires',
                ),
                _LegalRow(
                  label: 'Tax',
                  status: vehicle.taxStatus,
                  date: vehicle.taxDueDate,
                  dateLabel: 'due',
                ),
                if (vehicle.lookupError.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Space.md),
                  InlineNotice.warning(vehicle.lookupError),
                ],
              ],
            ),
          ),
        );
  }
}

/// The fitment, given the room it earns. A staggered set-up is shown as two
/// sizes rather than one, because loading the van off the front figure alone is
/// how a technician ends up making the trip twice.
class _TyreSpec extends StatelessWidget {
  const _TyreSpec({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    if (!vehicle.hasTyreSize) {
      return InlineNotice.warning(
        'No tyre size on record for this plate. Read it off the sidewall before loading.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: Radii.controlShape,
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('TYRE SIZE', style: palette.eyebrow),
          const SizedBox(height: Space.xs),
          Text(
            vehicle.fullTyreSpec,
            style: palette.plate.copyWith(fontSize: 21, letterSpacing: 1.4),
          ),
          if (vehicle.hasStaggeredFitment) ...<Widget>[
            const SizedBox(height: Space.xs),
            Text(
              'Staggered — rear ${vehicle.tyreSizeRear}',
              style: theme.textTheme.bodySmall?.copyWith(color: palette.warning),
            ),
          ],
          if (vehicle.tyreSizeOptions.length > 1) ...<Widget>[
            const SizedBox(height: Space.xs),
            Text(
              'Other fitments: ${vehicle.tyreSizeOptions.join(', ')}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (vehicle.tyrePressureFrontPsi != null) ...<Widget>[
            const SizedBox(height: Space.xs),
            Text(
              'Pressures ${vehicle.tyrePressureFrontPsi} psi front'
              '${vehicle.tyrePressureRearPsi == null ? '' : ' · ${vehicle.tyrePressureRearPsi} psi rear'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (vehicle.tyreSizeConfirmedByHuman) ...<Widget>[
            const SizedBox(height: Space.xs),
            Text('Confirmed on site, not from the lookup', style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// MOT or tax, coloured by how close it is. Nobody reads a date; everybody
/// reads red.
class _LegalRow extends StatelessWidget {
  const _LegalRow({
    required this.label,
    required this.status,
    required this.date,
    required this.dateLabel,
  });

  final String label;
  final String status;
  final DateTime? date;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final days = date?.difference(DateTime.now()).inDays;
    final tone = toneForDays(palette, days);

    return DetailRow(
      label,
      child: Text(
        <String>[
          if (status.isNotEmpty) status,
          if (date != null) '$dateLabel ${formatDate(date)}',
        ].join(' · '),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15, color: tone),
      ),
    );
  }
}

/// Green until a month out, amber inside it, red once it has gone. Shared by
/// everything on this screen that expires, so MOT, tax and insurance are all
/// read the same way.
Color toneForDays(Palette palette, int? days) {
  if (days == null) return palette.ink;
  if (days < 0) return palette.danger;
  if (days <= 30) return palette.warning;
  return palette.success;
}

/// The driver's own vehicle, and the paperwork attached to it.
class _MyCar extends ConsumerWidget {
  const _MyCar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cars = ref.watch(myVehiclesProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionHeader('My car'),
        cars.when(
          loading: () => const LoadingBlock(count: 1),
          error: (error, __) => InlineNotice(
            error is ApiException ? error.message : '$error',
            action: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => ref.read(myVehiclesProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
            ),
          ),
          data: (list) => list.isEmpty
              ? SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Add your registration and we keep its MOT and tax dates '
                        'in front of you.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: Space.lg),
                      OutlinedButton.icon(
                        onPressed: () => _addCar(context, ref),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Add my car'),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final car in list) ...<Widget>[
                      _MyCarCard(car: car),
                      const SizedBox(height: Space.md),
                    ],
                    OutlinedButton.icon(
                      onPressed: () => _addCar(context, ref),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Add another'),
                    ),
                  ],
                ),
        ),
      ],
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
}

/// One vehicle: what it is, then every date that can stop it being driven.
class _MyCarCard extends ConsumerStatefulWidget {
  const _MyCarCard({required this.car});

  final DriverVehicle car;

  @override
  ConsumerState<_MyCarCard> createState() => _MyCarCardState();
}

class _MyCarCardState extends ConsumerState<_MyCarCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this car?'),
        content: Text('${formatPlate(widget.car.plate)} comes off your account.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => ref.read(myVehiclesProvider.notifier).remove(widget.car.id));
  }

  @override
  Widget build(BuildContext context) {
    final car = widget.car;
    final palette = context.palette;
    final theme = Theme.of(context);
    final insurance = ref.watch(currentDriverProvider)?.documents.where(
          (document) => document.documentType == 'insurance',
        );
    final cover = insurance == null || insurance.isEmpty ? null : insurance.first;

    return SurfaceCard(
      accent: car.needsAttention ? palette.warning : (car.isPrimary ? palette.gold : null),
      wash: car.isPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              PlateBadge(formatPlate(car.plate)),
              const Spacer(),
              if (car.isPrimary) Icon(Icons.star_rounded, size: 22, color: palette.gold),
              IconButton(
                onPressed: _busy ? null : _remove,
                icon: Icon(Icons.delete_outline, color: palette.inkMuted),
                tooltip: 'Remove',
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(car.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.lg),

          _Expiry(label: 'MOT', status: car.motStatus, date: car.motExpiryDate, days: car.motDaysRemaining),
          _Expiry(label: 'Tax', status: car.taxStatus, date: car.taxDueDate, days: car.taxDaysRemaining),
          _Expiry(
            label: 'Insurance',
            status: cover == null ? 'Not uploaded' : cover.status,
            date: cover?.expiryDate,
            days: cover?.expiryDate?.difference(DateTime.now()).inDays,
          ),
          DetailRow('Fuel', value: car.fuelType),
          DetailRow('Engine', value: car.engineCapacity == null ? '' : '${car.engineCapacity} cc'),
          DetailRow('Year', value: car.year == null ? '' : '${car.year}'),

          const SizedBox(height: Space.md),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => ref.read(myVehiclesProvider.notifier).recheck(car.id)),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text('Re-check'),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/onboarding'),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Documents'),
                ),
              ),
            ],
          ),
          if (car.checkedAt != null) ...<Widget>[
            const SizedBox(height: Space.sm),
            Text(
              'Checked with DVLA ${formatRelative(car.checkedAt)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// A date that runs out, with the count of days left doing the talking.
class _Expiry extends StatelessWidget {
  const _Expiry({
    required this.label,
    required this.status,
    required this.date,
    required this.days,
  });

  final String label;
  final String status;
  final DateTime? date;
  final int? days;

  String get _remaining {
    if (days == null) return '';
    if (days! < 0) return 'expired ${-days!} days ago';
    if (days == 0) return 'expires today';
    return '$days days left';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tone = toneForDays(palette, days);
    final theme = Theme.of(context);

    return DetailRow(
      label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            date == null ? (status.isEmpty ? '—' : status) : formatDate(date),
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15, color: tone),
          ),
          if (_remaining.isNotEmpty)
            Text(
              <String>[if (status.isNotEmpty) status, _remaining].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: tone),
            ),
        ],
      ),
    );
  }
}

/// Adding a car is the plate and nothing else; DVLA fills in the rest.
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
      await ref.read(myVehiclesProvider.notifier).add(_plate.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.fieldError('plate') ?? error.message);
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
          Text('Add your car', style: theme.textTheme.displaySmall),
          const SizedBox(height: Space.xl),
          TextField(
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
