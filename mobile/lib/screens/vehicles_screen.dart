import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/vehicle_api.dart';
import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../providers/vehicles.dart';
import '../widgets/message_view.dart';

class VehiclesScreen extends ConsumerWidget {
  const VehiclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicles = ref.watch(myVehiclesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My vehicles')),
      body: vehicles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => MessageView(
          title: 'Could not load your vehicles',
          message: '$error',
          icon: Icons.wifi_off,
          onRetry: () => ref.invalidate(myVehiclesProvider),
        ),
        data: (saved) => saved.isEmpty
            ? const MessageView(
                title: 'No vehicles saved',
                message: 'Save your plate once and a call-out takes three taps.',
                icon: Icons.directions_car_outlined,
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: saved.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _VehicleCard(saved: saved[index]),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addVehicle(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add vehicle'),
      ),
    );
  }

  Future<void> _addVehicle(BuildContext context, WidgetRef ref) async {
    final plate = await showDialog<String>(
      context: context,
      builder: (context) => const _PlateDialog(),
    );
    if (plate == null || plate.isEmpty) return;
    try {
      await ref.read(myVehiclesProvider.notifier).add(plate);
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _VehicleCard extends ConsumerWidget {
  const _VehicleCard({required this.saved});

  final SavedVehicle saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = saved.vehicle;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    formatPlate(vehicle.plate),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                ),
                if (saved.isPrimary)
                  const Chip(label: Text('Default'), visualDensity: VisualDensity.compact),
              ],
            ),
            if (vehicle.title.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(vehicle.title),
            ],
            const SizedBox(height: 8),
            Text(
              vehicle.hasTyreSize
                  ? 'Tyres: ${vehicle.tyreSizeFront}'
                  : 'Tyre size unknown — add it so we arrive with the right tyre.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: () => _confirmTyre(context, ref),
                  child: Text(vehicle.hasTyreSize ? 'Correct tyre size' : 'Add tyre size'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => ref.read(myVehiclesProvider.notifier).remove(saved.id),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmTyre(BuildContext context, WidgetRef ref) async {
    final size = await showDialog<String>(
      context: context,
      builder: (context) => _TyreSizeDialog(initial: saved.vehicle.tyreSizeFront),
    );
    if (size == null || size.isEmpty) return;
    try {
      await ref.read(myVehiclesProvider.notifier).confirmTyreSize(saved.id, size);
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _PlateDialog extends StatefulWidget {
  const _PlateDialog();

  @override
  State<_PlateDialog> createState() => _PlateDialogState();
}

class _PlateDialogState extends State<_PlateDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a vehicle'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Number plate'),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Look up'),
        ),
      ],
    );
  }
}

class _TyreSizeDialog extends StatefulWidget {
  const _TyreSizeDialog({required this.initial});

  final String initial;

  @override
  State<_TyreSizeDialog> createState() => _TyreSizeDialogState();
}

class _TyreSizeDialogState extends State<_TyreSizeDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tyre size'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Size on the sidewall',
          hintText: '205/55 R16',
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
