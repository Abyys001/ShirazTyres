import 'package:flutter/material.dart';

import 'ui_kit.dart';

/// An empty or failed state, centred in whatever space it is given.
class MessageView extends StatelessWidget {
  const MessageView({
    required this.title,
    this.message = '',
    this.icon = Icons.info_outline,
    this.onRetry,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onRetry;

  /// Takes precedence over [onRetry] when the state has something better to
  /// offer than trying again.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppEmptyState(
        title: title,
        message: message,
        icon: icon,
        action: action ??
            (onRetry == null
                ? null
                : OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Try again'),
                  )),
      ),
    );
  }
}
