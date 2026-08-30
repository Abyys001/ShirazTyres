import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../models/invoice.dart';
import '../providers/jobs.dart';
import '../widgets/message_view.dart';

const _paymentMethods = <String, String>{
  'card_reader': 'Card reader',
  'payment_link': 'Payment link by SMS',
  'cash': 'Cash',
  'other': 'Other',
};

/// On-site invoicing (specification 7.1 steps 3 to 6).
///
/// The call-out fee is already on the invoice and cannot be taken off here; the
/// technician adds what they actually fitted, then takes the single payment.
class InvoiceScreen extends ConsumerStatefulWidget {
  const InvoiceScreen({required this.jobId, super.key});

  final int jobId;

  @override
  ConsumerState<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends ConsumerState<InvoiceScreen> {
  bool _busy = false;
  String _method = 'card_reader';

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFromPriceList() async {
    final items = await ref.read(priceListProvider.future);
    if (!mounted) return;

    final chosen = await showModalBottomSheet<ServiceItem>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final item in items)
              ListTile(
                title: Text(item.name),
                subtitle: Text('£${item.unitPrice}${item.unit.isEmpty ? '' : ' / ${item.unit}'}'),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );

    if (chosen != null) {
      await _run(() async {
        await ref.read(jobActionsProvider).addLine(widget.jobId, serviceItemId: chosen.id);
      });
    }
  }

  Future<void> _addFreeText() async {
    final description = TextEditingController();
    final price = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a line'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: description,
              decoration: const InputDecoration(labelText: 'What is it?'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: price,
              decoration: const InputDecoration(labelText: 'Price', prefixText: '£'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );

    if (ok == true && description.text.trim().isNotEmpty && price.text.trim().isNotEmpty) {
      await _run(() async {
        await ref.read(jobActionsProvider).addLine(
              widget.jobId,
              description: description.text.trim(),
              unitPrice: price.text.trim(),
            );
      });
    }
  }

  Future<void> _complete() async {
    await _run(() async {
      await ref.read(jobActionsProvider).complete(widget.jobId, paymentMethod: _method);
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(jobProvider(widget.jobId));

    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: job.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, __) => MessageView(title: 'Could not load the invoice', message: '$error'),
        data: (data) {
          final invoice = data.invoice;
          if (invoice == null) {
            return const MessageView(title: 'No invoice on this job yet');
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Card(
                child: Column(
                  children: <Widget>[
                    for (final line in invoice.lines)
                      ListTile(
                        title: Text(line.description),
                        subtitle: Text('${line.quantity} × £${line.unitPrice}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text('£${line.lineTotal}'),
                            if (invoice.isEditable && !line.isSystem)
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: _busy
                                    ? null
                                    : () => _run(() async {
                                          await ref
                                              .read(jobActionsProvider)
                                              .removeLine(widget.jobId, line.id);
                                        }),
                              ),
                          ],
                        ),
                      ),
                    const Divider(height: 1),
                    ListTile(
                      title: Text('VAT at ${invoice.vatRate}%'),
                      trailing: Text('£${invoice.vatAmount}'),
                    ),
                    ListTile(
                      title: const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                      trailing: Text(
                        '£${invoice.total}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (invoice.isEditable) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _addFromPriceList,
                        child: const Text('Price list'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _addFreeText,
                        child: const Text('Something else'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('How did they pay?', style: Theme.of(context).textTheme.titleSmall),
                RadioGroup<String>(
                  groupValue: _method,
                  onChanged: (value) => setState(() => _method = value ?? _method),
                  child: Column(
                    children: <Widget>[
                      for (final entry in _paymentMethods.entries)
                        RadioListTile<String>(value: entry.key, title: Text(entry.value)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _complete,
                  child: const Text('Take payment and finish'),
                ),
              ] else
                Text('This invoice is closed: ${invoice.statusDisplay}.'),
            ],
          );
        },
      ),
    );
  }
}
