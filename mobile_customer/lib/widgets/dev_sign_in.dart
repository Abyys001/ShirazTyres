import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/theme.dart';

/// Development-only sign-in helpers.
///
/// The API runs with `SMS_PROVIDER=mock`, which returns the verification code in
/// the response instead of texting it. This panel is where that code surfaces,
/// alongside the accounts `manage.py seed_demo` creates — so signing in during
/// development is two taps and never a guess.
///
/// It renders only when [AppConfig.devSignInEnabled] is true: a debug build
/// pointed at a local API. Nothing here reaches a release build.
class DevSignInPanel extends StatefulWidget {
  const DevSignInPanel({
    this.accounts = const <DevAccount>[],
    this.onUse,
    this.debugCode = '',
    this.extra,
    super.key,
  });

  /// Leave empty on a screen that has no phone field to fill — the panel then
  /// shows only the code the API handed back.
  final List<DevAccount> accounts;

  /// Fills the phone field with the chosen account's number.
  final ValueChanged<String>? onUse;

  /// The code the API handed back, once one has been requested.
  final String debugCode;

  /// An app-specific shortcut — the customer app puts its mock Google sign-in here.
  final Widget? extra;

  @override
  State<DevSignInPanel> createState() => _DevSignInPanelState();
}

class _DevSignInPanelState extends State<DevSignInPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (!AppConfig.devSignInEnabled) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final expandable = widget.accounts.isNotEmpty || widget.extra != null;

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: Radii.cardShape,
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.debugCode.isNotEmpty) _CodeBanner(code: widget.debugCode),
          InkWell(
            borderRadius: Radii.cardShape,
            onTap: expandable ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Row(
                children: <Widget>[
                  Icon(Icons.construction_outlined, size: 17, color: palette.inkSubtle),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text('DEVELOPMENT SIGN-IN', style: palette.eyebrow)),
                  if (expandable)
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: palette.inkSubtle,
                    ),
                ],
              ),
            ),
          ),
          if (_open && expandable) ...<Widget>[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Seeded by `make seed`. Tap one to fill the number, ask for a code, '
                    'and the code appears above — the mock SMS provider never sends a text.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: Space.md),
                  for (final account in widget.accounts)
                    _AccountRow(account: account, onTap: () => widget.onUse?.call(account.phone)),
                  if (widget.extra != null) ...<Widget>[
                    const SizedBox(height: Space.md),
                    widget.extra!,
                  ],
                  const SizedBox(height: Space.md),
                  Text(
                    'API: ${AppConfig.apiBaseUrl}',
                    style: palette.mono.copyWith(fontSize: 11, color: palette.inkSubtle),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.onTap});

  final DevAccount account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: Radii.controlShape,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm, horizontal: Space.sm),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(account.phone, style: palette.mono.copyWith(color: palette.ink)),
                  Text(
                    '${account.name} · ${account.note}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.north_west, size: 15, color: palette.inkSubtle),
          ],
        ),
      ),
    );
  }
}

class _CodeBanner extends StatelessWidget {
  const _CodeBanner({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      decoration: BoxDecoration(
        color: palette.goldDim,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.card)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.sms_outlined, size: 18, color: palette.gold),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('YOUR CODE', style: palette.eyebrow.copyWith(color: palette.gold)),
                const SizedBox(height: 2),
                Text(
                  code,
                  style: TextStyle(
                    fontFamily: Fonts.mono,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                    color: palette.gold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: Icon(Icons.copy_all_outlined, size: 18, color: palette.gold),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Code copied.')));
            },
          ),
        ],
      ),
    );
  }
}
