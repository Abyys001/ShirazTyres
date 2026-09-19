import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../models/job.dart';
import '../providers/jobs.dart';
import 'ui_kit.dart';

/// Confirm, then cancel — from wherever the customer is looking at the job.
///
/// The call-out can be dropped right up to the moment it is paid for, so the
/// question is asked differently depending on how far along it is: stopping a
/// search costs nobody anything, turning a technician round costs them a
/// journey, and it would be dishonest to ask both in the same words.
///
/// Returns true when the job was cancelled.
Future<bool> confirmAndCancel(BuildContext context, WidgetRef ref, CustomerJob job) async {
  Buzz.tap();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cancel this call-out?'),
      content: Text(_consequence(job.status)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Cancel it'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  try {
    await ref.read(cancelJobProvider)(job.id, '');
    return true;
  } on ApiException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    }
    return false;
  }
}

String _consequence(String status) {
  switch (status) {
    case 'accepted':
      return 'Your technician has accepted this job. We will let them know not to come.';
    case 'en_route':
      return 'Your technician is already on the way. We will turn them round.';
    case 'arrived':
    case 'in_progress':
      return 'Your technician is with you. Please speak to them first — '
          'anything already done may still be charged for.';
    default:
      return 'We will stop looking for a technician.';
  }
}
