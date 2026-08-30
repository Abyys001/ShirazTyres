import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../core/location.dart';
import '../models/public_config.dart';
import '../models/vehicle.dart';
import '../providers/api.dart';
import '../providers/jobs.dart';

/// The request flow (specification 4.2 to 4.5), in the order the specification
/// sets out: plate, tyre confirmation, location, issue, submit.
class RequestScreen extends ConsumerStatefulWidget {
  const RequestScreen({super.key});

  @override
  ConsumerState<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends ConsumerState<RequestScreen> {
  final _plate = TextEditingController();
  final _tyreSize = TextEditingController();
  final _description = TextEditingController();
  final _locationText = TextEditingController();

  Vehicle? _vehicle;
  String? _path; // 'confirmed' or 'overridden'
  bool _disclaimerAccepted = false;
  LocationResult? _position;
  Coverage? _coverage;
  String _issueType = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _plate.dispose();
    _tyreSize.dispose();
    _description.dispose();
    _locationText.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lookup() => _run(() async {
        final vehicle = await ref.read(jobApiProvider).lookup(_plate.text.trim());
        if (!mounted) return;
        setState(() {
          _vehicle = vehicle;
          _path = null;
          _disclaimerAccepted = false;
          _tyreSize.text = vehicle.tyreSizeFront;
        });
      });

  Future<void> _locate() => _run(() async {
        final fix = await currentLocation();
        if (!mounted) return;
        setState(() {
          _position = fix;
          _coverage = null;
          _error = fix.error;
        });
        if (!fix.isFixed) return;

        final coverage = await ref.read(jobApiProvider).coverage(
              latitude: fix.latitude!,
              longitude: fix.longitude!,
            );
        if (mounted) setState(() => _coverage = coverage);
      });

  Future<void> _submit() => _run(() async {
        final job = await ref.read(jobApiProvider).submit(
              plate: _plate.text.trim(),
              issueType: _issueType,
              description: _description.text.trim(),
              locationText: _locationText.text.trim(),
              latitude: _position!.latitude!,
              longitude: _position!.longitude!,
              accuracyMetres: _position!.accuracyMetres,
              confirmationPath: _path!,
              tyreSize: _tyreSize.text.trim(),
              disclaimerAccepted: _disclaimerAccepted,
            );
        ref.read(jobRevisionProvider.notifier).state++;
        if (mounted) context.go('/jobs/${job.id}');
      });

  bool get _tyreDone =>
      _path == 'confirmed' ||
      (_path == 'overridden' && _disclaimerAccepted && _tyreSize.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(publicConfigProvider);
    final covered = _coverage?.covered ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Request a technician')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          config.maybeWhen(
            data: (data) => data.isOpen
                ? const SizedBox.shrink()
                : Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(data.outOfHoursMessage),
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),

          const SizedBox(height: 8),
          Text('1. Your registration', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Registration', hintText: 'AB12 CDE'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _busy ? null : _lookup,
                child: const Text('Look up'),
              ),
            ],
          ),

          if (_vehicle != null) ...<Widget>[
            const SizedBox(height: 24),
            Text('2. Confirm your tyre size', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_vehicle!.description),
                    const SizedBox(height: 8),
                    Text(
                      _vehicle!.tyreSizeFront.isEmpty ? 'No size on record' : _vehicle!.tyreSizeFront,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (_vehicle!.tyreSizeOptions.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'More than one size is recorded for this model — check the sidewall of your tyre.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _vehicle!.tyreSizeFront.isEmpty
                        ? null
                        : () => setState(() {
                              _path = 'confirmed';
                              _disclaimerAccepted = false;
                              _tyreSize.text = _vehicle!.tyreSizeFront;
                            }),
                    style: _path == 'confirmed'
                        ? OutlinedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer)
                        : null,
                    child: const Text('That is correct'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _path = 'overridden';
                      _disclaimerAccepted = false;
                    }),
                    style: _path == 'overridden'
                        ? OutlinedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer)
                        : null,
                    child: const Text('Not my size'),
                  ),
                ),
              ],
            ),

            if (_path == 'overridden') ...<Widget>[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'If you give us a tyre size yourself, any mismatch — and anything that follows from '
                    'it, including a wasted call-out or a tyre that cannot be fitted — is your '
                    'responsibility. Our technician loads the van from the size you enter. The size is '
                    'printed on the sidewall of your existing tyre, for example 205/55R16.',
                  ),
                ),
              ),
              CheckboxListTile(
                value: _disclaimerAccepted,
                onChanged: (value) => setState(() => _disclaimerAccepted = value ?? false),
                title: const Text('I understand and accept responsibility for the size I enter.'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_disclaimerAccepted)
                TextField(
                  controller: _tyreSize,
                  decoration: const InputDecoration(labelText: 'Tyre size', hintText: '205/55R16'),
                  onChanged: (_) => setState(() {}),
                ),
            ],
          ],

          if (_tyreDone) ...<Widget>[
            const SizedBox(height: 24),
            Text('3. Where are you?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _locate,
              icon: const Icon(Icons.my_location),
              label: Text(_position?.isFixed == true ? 'Update my location' : 'Share my location'),
            ),
            if (_position?.isFixed == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Location shared to about ${_position!.accuracyMetres ?? '—'} m.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_coverage != null && !_coverage!.covered)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _coverage!.message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (covered)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: _locationText,
                  decoration: const InputDecoration(
                    labelText: 'Anything that helps us find you (optional)',
                    hintText: 'Hard shoulder, just past the Perivale exit',
                  ),
                ),
              ),
          ],

          if (_tyreDone && covered) ...<Widget>[
            const SizedBox(height: 24),
            Text('4. What happened?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            config.maybeWhen(
              data: (data) => DropdownButtonFormField<String>(
                initialValue: _issueType.isEmpty ? null : _issueType,
                decoration: const InputDecoration(labelText: 'Problem'),
                items: <DropdownMenuItem<String>>[
                  for (final issue in data.issueTypes)
                    DropdownMenuItem<String>(value: issue.value, child: Text(issue.label)),
                ],
                onChanged: (value) => setState(() => _issueType = value ?? ''),
              ),
              orElse: () => const LinearProgressIndicator(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Anything else we should know? (optional)'),
            ),
            config.maybeWhen(
              data: (data) => data.calloutFeeEnabled
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'A call-out fee of £${data.calloutFee} applies, plus parts and labour and VAT '
                        'at ${data.vatRate}%. You pay once the work is finished.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : const SizedBox.shrink(),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || _issueType.isEmpty ? null : _submit,
              child: const Text('Send my request'),
            ),
          ],

          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
