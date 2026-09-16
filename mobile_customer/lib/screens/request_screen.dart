import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_exception.dart';
import '../core/location.dart';
import '../core/theme.dart';
import '../models/public_config.dart';
import '../models/saved_vehicle.dart';
import '../models/vehicle.dart';
import '../providers/api.dart';
import '../providers/jobs.dart';
import '../providers/vehicles.dart';
import '../widgets/map_view.dart';
import '../widgets/plate_scan.dart';
import '../widgets/tyre_picker.dart';
import '../widgets/ui_kit.dart';
import 'location_picker_screen.dart';

/// The request flow (specification 4.2 to 4.5): plate, tyre confirmation,
/// location, issue, submit.
///
/// One question per screen. Somebody standing on a hard shoulder should be able
/// to answer what is in front of them without scrolling, without reading, and
/// without seeing a field they cannot yet fill in. The step bar says how much is
/// left, and the action is always the same button in the same place.
class RequestScreen extends ConsumerStatefulWidget {
  const RequestScreen({super.key});

  @override
  ConsumerState<RequestScreen> createState() => _RequestScreenState();
}

/// Icons for the issue types the API returns. Anything unrecognised falls back
/// to the generic glyph rather than disappearing off the grid.
const _issueIcons = <String, IconData>{
  'puncture': Icons.tire_repair,
  'blowout': Icons.warning_amber_rounded,
  'tyre_damage': Icons.report_gmailerrorred_outlined,
  'wheel_change': Icons.change_circle_outlined,
  'locking_nut': Icons.lock_outline,
  'other': Icons.more_horiz,
};

class _RequestScreenState extends ConsumerState<RequestScreen> {
  static const _steps = <String>['Your car', 'Tyre size', 'Which tyre', 'Where', 'Problem'];

  final _page = PageController();
  final _plate = TextEditingController();
  final _tyreSize = TextEditingController();
  final _description = TextEditingController();
  final _locationText = TextEditingController();

  int _step = 0;
  Vehicle? _vehicle;
  String? _path; // 'confirmed' or 'overridden'
  List<DamagedTyre> _damaged = const <DamagedTyre>[];
  bool _disclaimerAccepted = false;
  LocationResult? _position;

  /// The handset was asked for a fix and would not give one. The map stops being
  /// a secondary offer at that point and becomes the way forward.
  bool _fixRefused = false;
  Coverage? _coverage;
  String _issueType = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _page.dispose();
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
    } catch (error, stack) {
      // Only ApiException was caught here, so anything else — a response this
      // build cannot parse, a null where a position was expected — went nowhere:
      // the button stopped spinning and the screen said nothing, which read as
      // "Send request does nothing". Every failure now surfaces.
      debugPrintStack(stackTrace: stack, label: '$error');
      if (mounted) {
        setState(() => _error = 'Something went wrong sending this. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _error = null;
    });
    _page.animateToPage(step, duration: Motion.normal, curve: Curves.easeOut);
  }

  void _back() {
    if (_step == 0) {
      context.pop();
    } else {
      _goTo(_step - 1);
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
        Buzz.commit();
        _goTo(1);
      });

  Future<void> _locate() => _run(() async {
        final fix = await currentLocation();
        if (!mounted) return;
        setState(() {
          _position = fix;
          _coverage = null;
          _error = fix.error;
          _fixRefused = !fix.isFixed;
        });
        await _checkCoverage(fix);
      });

  /// Section 4.4: the pin is the fallback when the handset will not give a fix
  /// at all, so it has to reach the same coverage check as the device path.
  Future<void> _pick() async {
    final picked = await pickLocation(
      context,
      initial: _position?.point,
      note: _locationText.text,
      prompt: 'Drag the map until the pin is where your car is.',
      confirmLabel: 'This is where I am',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _position = picked.asResult;
      _coverage = null;
      _error = null;
      _fixRefused = false;
      _locationText.text = picked.note;
    });
    await _run(() => _checkCoverage(_position!));
  }

  Future<void> _checkCoverage(LocationResult fix) async {
    if (!fix.isFixed) return;
    final coverage = await ref.read(jobApiProvider).coverage(
          latitude: fix.latitude!,
          longitude: fix.longitude!,
        );
    if (!mounted) return;
    setState(() => _coverage = coverage);
    if (coverage.covered) Buzz.commit();
  }

  Future<void> _submit() => _run(() async {
        final position = _position;
        final path = _path;
        if (position == null || !position.isFixed || path == null) {
          // Reachable only if a step was skipped by a back-navigation race.
          setState(() => _error = 'Go back and confirm your tyre size and location.');
          return;
        }

        final job = await ref.read(jobApiProvider).submit(
              plate: _plate.text.trim(),
              issueType: _issueType,
              description: _description.text.trim(),
              locationText: _locationText.text.trim(),
              latitude: position.latitude!,
              longitude: position.longitude!,
              accuracyMetres: position.accuracyMetres,
              locationSource: position.source.wireName,
              confirmationPath: path,
              tyreSize: _tyreSize.text.trim(),
              disclaimerAccepted: _disclaimerAccepted,
              damaged: _damaged,
            );
        ref.read(jobRevisionProvider.notifier).state++;
        Buzz.commit();
        if (mounted) context.go('/jobs/${job.id}');
      });

  bool get _tyreDone =>
      _path == 'confirmed' ||
      (_path == 'overridden' && _disclaimerAccepted && _tyreSize.text.trim().isNotEmpty);

  bool get _covered => _coverage?.covered ?? false;

  /// What the one button at the bottom does on the step being shown.
  ({String label, IconData? icon, VoidCallback? action}) get _primary {
    switch (_step) {
      case 0:
        return (
          label: 'Find my car',
          icon: Icons.search,
          action: _plate.text.trim().length < 2 ? null : _lookup,
        );
      case 1:
        return (label: 'Continue', icon: null, action: _tyreDone ? () => _goTo(2) : null);
      case 2:
        // Optional on purpose. Somebody who cannot see the car, or does not
        // know, must still be able to get a van sent; the technician is told
        // what was and was not said rather than being given a guess.
        return (
          label: _damaged.isEmpty ? 'Skip — I am not sure' : 'Continue',
          icon: null,
          action: () => _goTo(3),
        );
      case 3:
        if (_covered) return (label: 'Continue', icon: null, action: () => _goTo(4));
        // The ladder matters. Asking a handset that has already refused, over and
        // over, was the dead end here: the one button on the screen stayed
        // "Share my location" and there was no way past this step on any phone
        // with location off. A refusal hands over to the map instead.
        if (_position?.isFixed == true) {
          return (label: 'Move the pin', icon: Icons.pin_drop_outlined, action: _pick);
        }
        if (_fixRefused) {
          return (label: 'Set it on the map', icon: Icons.map_outlined, action: _pick);
        }
        return (label: 'Share my location', icon: Icons.my_location, action: _locate);
      default:
        return (
          label: 'Send request',
          icon: Icons.send_rounded,
          action: _issueType.isEmpty ? null : _submit,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(publicConfigProvider);
    final primary = _primary;

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_step - 1);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
          title: Text(_steps[_step]),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
              child: StepBar(step: _step + 1, total: _steps.length),
            ),
          ),
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  _plateStep(config),
                  _tyreStep(),
                  _damagedStep(),
                  _locationStep(),
                  _issueStep(config),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
                child: InlineNotice(_error!),
              ),
          ],
        ),
        bottomNavigationBar: StickyBar(
          child: BusyButton(
            label: primary.label,
            icon: primary.icon,
            busy: _busy,
            onPressed: primary.action,
          ),
        ),
      ),
    );
  }

  Widget _stepBody({required String question, String hint = '', required List<Widget> children}) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xl),
      children: <Widget>[
        Text(question, style: theme.textTheme.headlineMedium),
        if (hint.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.xs),
          Text(hint, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Space.xl),
        ...children,
      ],
    );
  }

  // Step 1 -------------------------------------------------------------------

  Widget _plateStep(AsyncValue<PublicConfig> config) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final saved = ref.watch(savedVehiclesProvider).valueOrNull ?? const <SavedVehicle>[];
    final looking = _busy && _step == 0;

    return _stepBody(
      question: 'Registration?',
      children: <Widget>[
        config.maybeWhen(
          data: (data) => data.isOpen
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: Space.lg),
                  child: InlineNotice.warning(data.outOfHoursMessage),
                ),
          orElse: () => const SizedBox.shrink(),
        ),

        // The lookup goes out to the DVLA and then to the tyre database, and
        // either can take a few seconds. Rather than a button that dims, the
        // plate is shown being read.
        AnimatedSize(
          duration: Motion.normal,
          curve: Curves.easeOut,
          child: looking
              ? PlateScan(plate: _plate.text.trim())
              : TextField(
                  controller: _plate,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _busy || _plate.text.trim().length < 2 ? null : _lookup(),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9 ]')),
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: palette.plate.copyWith(fontSize: 30, letterSpacing: 5),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'AB12 CDE',
                    contentPadding: EdgeInsets.symmetric(vertical: 26),
                    hintStyle: TextStyle(
                      fontFamily: Fonts.mono,
                      fontSize: 30,
                      letterSpacing: 5,
                      color: palette.inkSubtle,
                    ),
                  ),
                ),
        ),

        // A car already in the garage is one tap, which is the whole point of
        // having saved it.
        if (saved.isNotEmpty && !looking) ...<Widget>[
          const SizedBox(height: Space.xxl),
          Text('Your cars', style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.md),
          for (final car in saved)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                onTap: () {
                  _plate.text = car.plate.replaceAll(' ', '');
                  _lookup();
                },
                child: Row(
                  children: <Widget>[
                    PlateBadge(car.plate, dense: true),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        car.title,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: palette.inkSubtle),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  // Step 2 -------------------------------------------------------------------

  // Step 3 -------------------------------------------------------------------

  /// Which wheel, on a picture of the car.
  ///
  /// The van is loaded from this. "The front one" and "driver's side" were the
  /// answers a text field produced, and neither is enough to bring the right
  /// tyre to the right corner — so the question is asked as a diagram the
  /// customer can point at while standing next to the car.
  Widget _damagedStep() {
    return _stepBody(
      question: 'Which tyre has gone?',
      hint: 'Tap every wheel that needs looking at. You can pick more than one.',
      children: <Widget>[
        TyrePicker(
          selected: _damaged,
          onChanged: (damaged) => setState(() => _damaged = damaged),
        ),
      ],
    );
  }

  Widget _tyreStep() {
    final palette = context.palette;
    final vehicle = _vehicle;
    if (vehicle == null) return const SizedBox.shrink();
    final overriding = _path == 'overridden';
    final typed = _tyreSize.text.trim();

    return _stepBody(
      question: 'Is this your tyre?',
      hint: vehicle.description,
      children: <Widget>[
        _Sidewall(size: vehicle.tyreSizeFront, confirmed: _path == 'confirmed'),
        if (vehicle.tyreSizeOptions.length > 1) ...<Widget>[
          const SizedBox(height: Space.md),
          InlineNotice.info('Several sizes fit this model — check your sidewall.'),
        ],
        const SizedBox(height: Space.xl),

        _TyreAnswer(
          label: "That's the one",
          icon: Icons.check_circle,
          tone: palette.success,
          selected: _path == 'confirmed',
          onTap: vehicle.tyreSizeFront.isEmpty
              ? null
              : () => setState(() {
                    _path = 'confirmed';
                    _disclaimerAccepted = false;
                    _tyreSize.text = vehicle.tyreSizeFront;
                  }),
        ),
        const SizedBox(height: Space.md),
        _TyreAnswer(
          label: 'Mine is different',
          icon: Icons.edit_road,
          tone: palette.warning,
          selected: overriding,
          onTap: () => setState(() {
            _path = 'overridden';
            _disclaimerAccepted = false;
            _tyreSize.clear();
          }),
        ),

        // Path B (specification 4.3). Both figures are kept on the job, and the
        // notice is signed for with a deliberate drag rather than a tick box:
        // this is the one decision on the flow that costs the customer money if
        // they get it wrong, so it is the one that takes a second to make.
        AnimatedSize(
          duration: Motion.normal,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !overriding
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: Space.lg),
                  child: _OwnSizeCard(
                    controller: _tyreSize,
                    accepted: _disclaimerAccepted,
                    onChanged: () => setState(() => _disclaimerAccepted = false),
                    onAccept: () => setState(() => _disclaimerAccepted = true),
                    onReopen: () => setState(() => _disclaimerAccepted = false),
                    onExplain: _showTyreTerms,
                    size: typed,
                  ),
                ),
        ),
      ],
    );
  }

  void _showTyreTerms() {
    final palette = context.palette;
    Buzz.tap();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: palette.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('The size you enter', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: Space.xl),
              const _TermPoint(
                icon: Icons.local_shipping_outlined,
                text: 'The van is loaded from your size.',
              ),
              const _TermPoint(
                icon: Icons.receipt_long_outlined,
                text: 'Wrong size, wasted call-out — and the cost is yours.',
              ),
              const _TermPoint(
                icon: Icons.straighten,
                text: 'It is printed on the tyre already on the car.',
              ),
              const SizedBox(height: Space.xl),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Step 3 -------------------------------------------------------------------

  Widget _locationStep() {
    final palette = context.palette;
    final theme = Theme.of(context);
    final point = _position?.point;
    final pinned = _position?.isPinned ?? false;

    return _stepBody(
      question: 'Where are you?',
      hint: point != null ? '' : 'Your phone knows better than a postcode.',
      children: <Widget>[
        if (point == null)
          SurfaceCard(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              children: <Widget>[
                Icon(Icons.location_searching, size: 44, color: palette.inkSubtle),
                const SizedBox(height: Space.lg),
                Text('Not shared yet', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  'Share your location, or drop a pin on the map yourself.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          )
        else
          SurfaceCard(
            accent: _covered
                ? palette.success
                : _coverage != null
                    ? palette.danger
                    : null,
            padding: const EdgeInsets.all(Space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                MiniMap(point: point, onTap: _busy ? null : _pick),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.sm, Space.xs),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        pinned ? Icons.pin_drop : Icons.gps_fixed,
                        size: 18,
                        color: _covered ? palette.success : palette.inkMuted,
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          pinned
                              ? 'Pinned by hand'
                              : 'Your phone’s fix'
                                  '${_position!.accuracyMetres == null ? '' : ' · about ${_position!.accuracyMetres} m'}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(point.pretty, style: palette.mono),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_coverage != null && !_coverage!.covered) ...<Widget>[
          const SizedBox(height: Space.md),
          InlineNotice(_coverage!.message),
        ],
        const SizedBox(height: Space.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(point == null ? 'Set it on the map' : 'Move the pin'),
            ),
            if (point != null)
              TextButton.icon(
                onPressed: _busy ? null : _locate,
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text('Use my phone'),
              ),
          ],
        ),
        if (_covered) ...<Widget>[
          const SizedBox(height: Space.md),
          TextField(
            controller: _locationText,
            decoration: const InputDecoration(
              labelText: 'Landmark (optional)',
              hintText: 'Hard shoulder, past the Perivale exit',
            ),
          ),
        ],
      ],
    );
  }

  // Step 4 -------------------------------------------------------------------

  Widget _issueStep(AsyncValue<PublicConfig> config) => _stepBody(
        question: 'What happened?',
        children: <Widget>[
          config.maybeWhen(
            data: (data) => ChoiceGrid(
              children: <Widget>[
                for (final issue in data.issueTypes)
                  ChoiceTile(
                    label: issue.label,
                    icon: _issueIcons[issue.value] ?? Icons.help_outline,
                    selected: _issueType == issue.value,
                    onTap: () => setState(() => _issueType = issue.value),
                  ),
              ],
            ),
            orElse: () => const LoadingBlock(count: 3),
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Anything else? (optional)'),
          ),
          config.maybeWhen(
            data: (data) => data.calloutFeeEnabled
                ? Padding(
                    padding: const EdgeInsets.only(top: Space.lg),
                    child: _FeeSummary(fee: data.calloutFee, vatRate: data.vatRate),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      );
}

/// What it costs, as three figures rather than a sentence. The point of the
/// panel is that nobody submits a request without having seen the call-out fee.
class _FeeSummary extends StatelessWidget {
  const _FeeSummary({required this.fee, required this.vatRate});

  final String fee;
  final String vatRate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      child: Row(
        children: <Widget>[
          Icon(Icons.receipt_long_outlined, size: 20, color: palette.inkSubtle),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('£$fee call-out', style: theme.textTheme.titleMedium),
                Text('Plus parts and $vatRate% VAT · pay when done',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The manufacturer's figure, set the way it appears on the tyre: a band of
/// tread with the size cut into it. It is the largest thing on the step because
/// it is the only thing being asked about.
class _Sidewall extends StatelessWidget {
  const _Sidewall({required this.size, required this.confirmed});

  final String size;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final known = size.isNotEmpty;

    return AnimatedContainer(
      duration: Motion.normal,
      height: 156,
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: Radii.cardShape,
        border: Border.all(color: confirmed ? palette.success : palette.goldDim, width: confirmed ? 2 : 1),
      ),
      child: Stack(
        children: <Widget>[
          const Positioned(left: 0, right: 0, top: 0, height: 16, child: _Tread()),
          const Positioned(left: 0, right: 0, bottom: 0, height: 16, child: _Tread()),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  known ? size : 'No size on record',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontFamily: Fonts.mono,
                    color: known ? palette.gold : palette.inkSubtle,
                  ),
                ),
                const SizedBox(height: Space.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      known ? Icons.verified_outlined : Icons.help_outline,
                      size: 17,
                      color: palette.inkMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      known ? 'From the manufacturer' : 'Type yours below',
                      style: theme.textTheme.titleMedium?.copyWith(color: palette.inkMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The tread blocks along the edges of the sidewall panel.
class _Tread extends StatelessWidget {
  const _Tread();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _TreadPainter(context.palette));
}

class _TreadPainter extends CustomPainter {
  const _TreadPainter(this.palette);

  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = palette.goldDim;
    const block = 9.0;
    const gap = 8.0;
    for (var x = gap; x < size.width - block; x += block + gap) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height * 0.3, block, size.height * 0.4),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TreadPainter old) => old.palette != palette;
}

/// One of the two answers. Full width, thumb-height, and it says what it means
/// in three words — no caption underneath explaining the three words.
class _TyreAnswer extends StatelessWidget {
  const _TyreAnswer({
    required this.label,
    required this.icon,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tone;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final enabled = onTap != null;

    return Material(
      color: Colors.transparent,
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
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          decoration: BoxDecoration(
            color: selected ? tone.withValues(alpha: 0.12) : palette.surface,
            borderRadius: Radii.cardShape,
            border: Border.all(color: selected ? tone : palette.line, width: selected ? 2 : 1),
          ),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: Motion.fast,
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? tone.withValues(alpha: 0.2) : palette.surfaceRaised,
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: enabled ? (selected ? tone : palette.inkMuted) : palette.lineStrong,
                ),
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: enabled ? palette.ink : palette.inkSubtle,
                  ),
                ),
              ),
              AnimatedScale(
                duration: Motion.fast,
                scale: selected ? 1 : 0,
                child: Icon(Icons.check_circle, color: tone, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Path B: type the size, then sign for it.
///
/// The signature is a drag rather than a tick because it is the one answer on
/// this flow that costs the customer money if it is wrong, and because a tick
/// box with a sentence beside it is exactly the shape people tick without
/// reading.
class _OwnSizeCard extends StatelessWidget {
  const _OwnSizeCard({
    required this.controller,
    required this.accepted,
    required this.size,
    required this.onChanged,
    required this.onAccept,
    required this.onReopen,
    required this.onExplain,
  });

  final TextEditingController controller;
  final bool accepted;
  final String size;
  final VoidCallback onChanged;
  final VoidCallback onAccept;
  final VoidCallback onReopen;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return SurfaceCard(
      accent: accepted ? palette.success : palette.warning,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.straighten, size: 20, color: palette.inkMuted),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text('Read it off the tyre wall', style: theme.textTheme.titleLarge),
              ),
              TextButton(onPressed: onExplain, child: const Text('Why')),
            ],
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: controller,
            autofocus: true,
            enabled: !accepted,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            style: palette.plate.copyWith(fontSize: 26, letterSpacing: 2),
            decoration: InputDecoration(
              hintText: '205/55R16',
              hintStyle: palette.plate.copyWith(
                fontSize: 26,
                letterSpacing: 2,
                color: palette.inkSubtle,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: Space.lg),
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: Space.lg),
          AnimatedSize(
            duration: Motion.normal,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: accepted
                ? Row(
                    children: <Widget>[
                      Icon(Icons.verified_user, size: 22, color: palette.success),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text('Signed for', style: theme.textTheme.titleLarge),
                      ),
                      TextButton(onPressed: onReopen, child: const Text('Change')),
                    ],
                  )
                : SlideAction(
                    label: size.isEmpty ? 'Type the size first' : 'Slide: this size is mine',
                    icon: Icons.verified_user_outlined,
                    tone: palette.warning,
                    onConfirm: size.isEmpty
                        ? null
                        : () async {
                            onAccept();
                          },
                  ),
          ),
        ],
      ),
    );
  }
}

/// One line of the responsibility notice: a picture and a short sentence, so the
/// sheet is three things to look at rather than two paragraphs to read.
class _TermPoint extends StatelessWidget {
  const _TermPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: context.palette.surfaceRaised),
              child: Icon(icon, size: 20, color: context.palette.gold),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
      );
}
