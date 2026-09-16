import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../models/invoice.dart';
import '../providers/jobs.dart';
import '../widgets/message_view.dart';
import '../widgets/ui_kit.dart';

const _paymentMethods = <String, ({String label, IconData icon})>{
  'card_reader': (label: 'Card', icon: Icons.credit_card),
  'payment_link': (label: 'SMS link', icon: Icons.link),
  'cash': (label: 'Cash', icon: Icons.payments_outlined),
  'other': (label: 'Other', icon: Icons.more_horiz),
};

/// On-site invoicing (specification 7.1 steps 3 to 6).
///
/// The call-out fee is already on the invoice and cannot be taken off here; the
/// technician adds what they actually fitted, then takes the single payment.
///
/// Taking the money closes the job for good, so it is a slide rather than a tap,
/// and the amount is on the control itself — the last thing read before it goes
/// through is the figure being charged.
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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFromPriceList() async {
    final palette = context.palette;
    Buzz.tap();
    final items = await ref.read(priceListProvider.future);
    if (!mounted) return;

    final chosen = await showModalBottomSheet<ServiceItem>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          children: <Widget>[
            const SectionHeader('Price list'),
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                minVerticalPadding: Space.md,
                title: Text(item.name),
                subtitle: Text(item.unit.isEmpty ? 'each' : item.unit),
                trailing: Text('£${item.unitPrice}', style: palette.mono.copyWith(color: palette.ink)),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );

    if (chosen != null) {
      await _run(
        () => ref.read(jobActionsProvider).addLine(widget.jobId, serviceItemId: chosen.id),
      );
    }
  }

  Future<void> _addFreeText() async {
    Buzz.tap();
    final description = TextEditingController();
    final price = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Add a line', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: Space.xl),
                TextField(
                  controller: description,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'What is it?'),
                ),
                const SizedBox(height: Space.md),
                TextField(
                  controller: price,
                  decoration: const InputDecoration(labelText: 'Price', prefixText: '£ '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: Space.lg),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok == true && description.text.trim().isNotEmpty && price.text.trim().isNotEmpty) {
      await _run(
        () => ref.read(jobActionsProvider).addLine(
              widget.jobId,
              description: description.text.trim(),
              unitPrice: price.text.trim(),
            ),
      );
    }
  }

  Future<void> _complete() => _run(() async {
        await ref.read(jobActionsProvider).complete(widget.jobId, paymentMethod: _method);
        if (mounted) Navigator.of(context).pop();
      });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final job = ref.watch(jobProvider(widget.jobId));
    final invoice = job.valueOrNull?.invoice;

    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: job.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Space.lg),
          child: LoadingBlock(count: 3),
        ),
        error: (error, __) => MessageView(title: 'Could not load the invoice', message: '$error'),
        data: (data) => data.invoice == null
            ? const MessageView(
                title: 'No invoice on this job yet',
                icon: Icons.receipt_long_outlined,
              )
            : _body(data.invoice!),
      ),
      bottomNavigationBar: invoice == null || !invoice.isEditable
          ? null
          : StickyBar(
              child: SlideAction(
                label: 'Slide to take £${invoice.total}',
                icon: Icons.done_all,
                busy: _busy,
                tone: palette.success,
                onConfirm: _complete,
              ),
            ),
    );
  }

  Widget _body(Invoice invoice) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
      children: <Widget>[
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          child: Column(
            children: <Widget>[
              for (final line in invoice.lines)
                _LineRow(
                  line: line,
                  removable: invoice.isEditable && !line.isSystem,
                  busy: _busy,
                  onRemove: () => _run(
                    () => ref.read(jobActionsProvider).removeLine(widget.jobId, line.id),
                  ),
                ),
              const Divider(height: Space.xl),
              _TotalRow(label: 'Subtotal', amount: invoice.subtotal),
              _TotalRow(label: 'VAT at ${invoice.vatRate}%', amount: invoice.vatAmount),
              const SizedBox(height: Space.sm),
              Row(
                children: <Widget>[
                  Expanded(child: Text('Total', style: theme.textTheme.titleLarge)),
                  Text(
                    '£${invoice.total}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontFamily: Fonts.mono,
                      color: palette.gold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (!invoice.isEditable) ...<Widget>[
          const SizedBox(height: Space.lg),
          InlineNotice.info('This invoice is closed: ${invoice.statusDisplay}.'),
        ] else ...<Widget>[
          const SizedBox(height: Space.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.list_alt, size: 18),
                  onPressed: _busy ? null : _addFromPriceList,
                  label: const Text('Price list'),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: _busy ? null : _addFreeText,
                  label: const Text('Other'),
                ),
              ),
            ],
          ),

          const SizedBox(height: Space.xl),
          const SectionHeader('How did they pay?'),
          ChoiceGrid(
            children: <Widget>[
              for (final entry in _paymentMethods.entries)
                ChoiceTile(
                  label: entry.value.label,
                  icon: entry.value.icon,
                  selected: _method == entry.key,
                  onTap: () => setState(() => _method = entry.key),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.removable,
    required this.busy,
    required this.onRemove,
  });

  final InvoiceLine line;
  final bool removable;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(line.description, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15)),
                Text('${line.quantity} × £${line.unitPrice}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Text('£${line.lineTotal}', style: palette.mono.copyWith(color: palette.ink)),
          if (removable)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: busy
                  ? null
                  : () {
                      Buzz.tap();
                      onRemove();
                    },
            )
          else
            const SizedBox(width: Space.sm),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Text('£$amount', style: palette.mono),
        ],
      ),
    );
  }
}
