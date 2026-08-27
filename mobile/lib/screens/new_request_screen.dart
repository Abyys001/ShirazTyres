import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../core/location.dart';
import '../models/booking.dart';
import '../models/vehicle.dart';
import '../providers/api.dart';
import '../providers/auth.dart';
import '../providers/bookings.dart';
import '../providers/vehicles.dart';

class NewRequestScreen extends ConsumerStatefulWidget {
  const NewRequestScreen({super.key});

  @override
  ConsumerState<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends ConsumerState<NewRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _plate = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _tyreSize = TextEditingController();

  String _issue = 'puncture';
  Vehicle? _vehicle;
  LocationResult _fix = const LocationResult();
  bool _lookingUp = false;
  bool _locating = false;
  bool _submitting = false;
  String? _plateError;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill from the saved vehicle so the common case is three taps.
    final primary = ref.read(primaryVehicleProvider);
    if (primary != null) {
      _plate.text = formatPlate(primary.vehicle.plate);
      _vehicle = primary.vehicle;
      _tyreSize.text = primary.vehicle.tyreSizeFront;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void dispose() {
    _plate.dispose();
    _location.dispose();
    _description.dispose();
    _tyreSize.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final fix = await currentLocation();
    if (!mounted) return;
    setState(() {
      _fix = fix;
      _locating = false;
    });
  }

  Future<void> _lookup() async {
    final plate = _plate.text.trim();
    if (plate.isEmpty) return;
    setState(() {
      _lookingUp = true;
      _plateError = null;
    });
    try {
      final vehicle = await ref.read(vehicleApiProvider).lookup(plate);
      if (!mounted) return;
      setState(() {
        _vehicle = vehicle;
        if (_tyreSize.text.isEmpty) _tyreSize.text = vehicle.tyreSizeFront;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _vehicle = null;
          _plateError = error.fieldError('plate') ?? error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_fix.isFixed && _location.text.trim().isEmpty) {
      setState(() => _error = 'Share your location or type where you are.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final driver = ref.read(currentDriverProvider);
      final booking = await ref.read(bookingApiProvider).create(
            issueType: _issue,
            contactPhone: driver?.phone ?? '',
            plate: _plate.text.trim(),
            contactName: driver?.name ?? '',
            description: _description.text.trim(),
            tyreSize: _tyreSize.text.trim(),
            locationText: _location.text.trim(),
            latitude: _fix.latitude,
            longitude: _fix.longitude,
          );
      ref.read(myBookingsProvider.notifier).prepend(booking);
      if (mounted) context.pushReplacement('/bookings/${booking.id}');
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request a call-out')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              _sectionTitle(context, 'What has happened?'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final issue in IssueType.values)
                    ChoiceChip(
                      label: Text(IssueType.label(issue)),
                      selected: _issue == issue,
                      onSelected: (_) => setState(() => _issue = issue),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _sectionTitle(context, 'Your vehicle'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _plate,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Number plate',
                  errorText: _plateError,
                  suffixIcon: _lookingUp
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: _lookup,
                        ),
                ),
                onFieldSubmitted: (_) => _lookup(),
              ),
              if (_vehicle != null) ...<Widget>[
                const SizedBox(height: 8),
                _VehicleSummary(vehicle: _vehicle!),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _tyreSize,
                decoration: const InputDecoration(
                  labelText: 'Tyre size (if you know it)',
                  hintText: '205/55 R16',
                  helperText: 'Helps us load the right tyre before we set off.',
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle(context, 'Where are you?'),
              const SizedBox(height: 8),
              _LocationBanner(fix: _fix, busy: _locating, onRetry: _locate),
              const SizedBox(height: 12),
              TextFormField(
                controller: _location,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Address or landmark',
                  hintText: 'M6 northbound, just past junction 4',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Anything else we should know?',
                  hintText: 'Front nearside, spare is flat, two children in the car.',
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text('Send request'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);
}

class _VehicleSummary extends StatelessWidget {
  const _VehicleSummary({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              vehicle.title.isEmpty ? vehicle.label : vehicle.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              vehicle.hasTyreSize
                  ? 'Tyre size on file: ${vehicle.tyreSizeFront}'
                  : 'No tyre size on file — tell us if you know it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationBanner extends StatelessWidget {
  const _LocationBanner({required this.fix, required this.busy, required this.onRetry});

  final LocationResult fix;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
        title: Text('Getting your location…'),
      );
    }
    if (fix.isFixed) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.my_location, color: Color(0xFF2E7D32)),
        title: const Text('Location shared'),
        subtitle: Text(
          '${fix.latitude!.toStringAsFixed(5)}, ${fix.longitude!.toStringAsFixed(5)}',
        ),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.location_off_outlined),
      title: Text(fix.error ?? 'Location not shared'),
      subtitle: const Text('Type where you are instead, or try again.'),
      trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
    );
  }
}
