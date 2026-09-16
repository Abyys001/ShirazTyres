import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_exception.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../providers/jobs.dart';
import '../widgets/message_view.dart';
import '../widgets/status_chip.dart';
import '../widgets/tyre_damage.dart';
import '../widgets/ui_kit.dart';
import 'invoice_screen.dart';

/// One job, from accepted to paid (specification 5 and 7).
///
/// The next action lives in a bar pinned to the bottom rather than at the end of
/// a scroll: at the roadside the technician is looking for one control, and it
/// should be under their thumb wherever the page happens to be. It is a slide
/// rather than a tap, because every one of these steps is on the record and none
/// of them can be undone from the van.
class JobScreen extends ConsumerStatefulWidget {
  const JobScreen({required this.jobId, super.key});

  final int jobId;

  @override
  ConsumerState<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends ConsumerState<JobScreen> {
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

  Future<void> _correctTyre(Job job) async {
    final palette = context.palette;
    Buzz.tap();
    final controller = TextEditingController(text: job.tyreSize);
    final size = await showModalBottomSheet<String>(
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
                Text('Actual tyre size', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: Space.xs),
                Text(
                  'The office and the customer record both update.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.xl),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: palette.plate.copyWith(fontSize: 22, letterSpacing: 1.5),
                  decoration: const InputDecoration(hintText: '205/55R16'),
                ),
                const SizedBox(height: Space.lg),
                FilledButton(
                  onPressed: () => Navigator.pop(context, controller.text.trim()),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (size != null && size.isNotEmpty) {
      await _run(() => ref.read(jobActionsProvider).correctTyre(job.id, size));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final job = ref.watch(jobProvider(widget.jobId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          job.valueOrNull?.reference ?? 'Job',
          style: palette.mono.copyWith(fontSize: 17, fontWeight: FontWeight.w700, color: palette.ink),
        ),
      ),
      body: job.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Space.lg),
          child: LoadingBlock(count: 3),
        ),
        error: (error, __) => MessageView(
          title: 'Could not load this job',
          message: '$error',
          onRetry: () => ref.invalidate(jobProvider(widget.jobId)),
        ),
        data: _body,
      ),
      bottomNavigationBar: job.maybeWhen(
        data: _actionBar,
        orElse: () => null,
      ),
    );
  }

  Widget _body(Job data) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
      children: <Widget>[
        // What the job is, and the two things a technician reaches for on the
        // way to it — both at full size, before any of the paperwork.
        SurfaceCard(
          accent: palette.status(data.status),
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: Text(data.issueHeadline, style: theme.textTheme.headlineSmall)),
                  const SizedBox(width: Space.md),
                  StatusChip(status: data.status, label: JobStatus.label(data.status)),
                ],
              ),
              const SizedBox(height: Space.md),
              Row(
                children: <Widget>[
                  PlateBadge(formatPlate(data.plate), dense: true),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      data.tyreSize.isEmpty ? data.contactName : data.tyreSize,
                      style: palette.mono.copyWith(color: palette.ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.place_outlined, size: 15, color: palette.inkSubtle),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      data.locationText.isEmpty ? 'Position shared' : data.locationText,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const Divider(height: Space.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  QuickAction(
                    label: 'Navigate',
                    icon: Icons.navigation,
                    tone: palette.gold,
                    onTap: data.mapsUrl.isEmpty
                        ? null
                        : () => launchUrl(
                              Uri.parse(data.mapsUrl),
                              mode: LaunchMode.externalApplication,
                            ),
                  ),
                  QuickAction(
                    label: 'Call',
                    icon: Icons.phone,
                    tone: palette.gold,
                    onTap: data.contactPhone.isEmpty
                        ? null
                        : () => launchUrl(Uri.parse('tel:${data.contactPhone}')),
                  ),
                  QuickAction(
                    label: 'Wrong size',
                    icon: Icons.edit_outlined,
                    onTap: _busy ? null : () => _correctTyre(data),
                  ),
                ],
              ),
            ],
          ),
        ),

        // A customer-supplied size decides which tyre comes out of the van, so
        // it stays on the surface where a folded-away detail would not.
        if (data.sizeFromCustomer) ...<Widget>[
          const SizedBox(height: Space.md),
          InlineNotice.warning(
            'Size from the customer. Lookup said '
            '${data.lookedUpTyreSize.isEmpty ? "nothing" : data.lookedUpTyreSize}.',
          ),
        ],
        if (data.correctedOnSite) ...<Widget>[
          const SizedBox(height: Space.md),
          InlineNotice(
            'Corrected on site.',
            tone: palette.success,
            icon: Icons.check_circle_outline,
          ),
        ],

        // Which wheel, on the surface rather than folded away: it decides what
        // comes off the van, and finding out on arrival is the whole problem
        // this was built to stop.
        const SizedBox(height: Space.lg),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('WHICH TYRE', style: palette.eyebrow),
              const SizedBox(height: Space.md),
              TyreDamageView(damaged: data.damaged),
            ],
          ),
        ),

        const SizedBox(height: Space.lg),
        ExpandableCard(
          title: 'Vehicle and customer',
          icon: Icons.directions_car_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DetailRow('Vehicle', value: data.vehicle?.description ?? ''),
              DetailRow('Tyre', value: data.tyreSize, mono: true),
              DetailRow('Name', value: data.contactName),
              DetailRow('Phone', value: data.contactPhone, mono: true),
              if (data.description.isNotEmpty) DetailRow('Notes', value: data.description),
              DetailRow('Requested', value: formatDateTime(data.createdAt)),
            ],
          ),
        ),

        if (data.status == JobStatus.completed) ...<Widget>[
          const SizedBox(height: Space.lg),
          SurfaceCard(
            accent: palette.success,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: StatBlock(
                    value: '£${data.invoice?.total ?? '—'}',
                    label: 'total paid',
                    tone: palette.success,
                  ),
                ),
                OutlinedButton(
                  onPressed: () {
                    Buzz.tap();
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => InvoiceScreen(jobId: data.id)),
                    );
                  },
                  child: const Text('Invoice'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The one thing to do next, pinned above the gesture bar.
  Widget? _actionBar(Job data) {
    final advance = data.nextStatus;
    final invoicing = data.status == JobStatus.inProgress;
    if (advance == null && !invoicing) return null;

    return StickyBar(
      secondary: advance != null && invoicing ? _invoiceButton(data) : null,
      child: advance != null
          ? SlideAction(
              label: JobStatus.actionLabel(advance),
              busy: _busy,
              onConfirm: () => _run(() => ref.read(jobActionsProvider).advance(data)),
            )
          : _invoiceButton(data),
    );
  }

  Widget _invoiceButton(Job data) => OutlinedButton.icon(
        icon: const Icon(Icons.receipt_long_outlined, size: 18),
        label: const Text('Invoice and payment'),
        onPressed: _busy
            ? null
            : () {
                Buzz.tap();
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => InvoiceScreen(jobId: data.id)),
                );
              },
      );
}
