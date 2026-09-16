import 'package:intl/intl.dart';

final _dateTime = DateFormat('d MMM, HH:mm');
final _date = DateFormat('d MMM yyyy');
final _time = DateFormat('HH:mm');

String formatDateTime(DateTime? value) => value == null ? '—' : _dateTime.format(value);

String formatTime(DateTime? value) => value == null ? '—' : _time.format(value);

/// For anything that expires. The time of day is noise on an MOT date.
String formatDate(DateTime? value) => value == null ? '—' : _date.format(value);

String formatRelative(DateTime? value) {
  if (value == null) return '—';
  final elapsed = DateTime.now().difference(value);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours} h ago';
  return formatDateTime(value);
}

/// UK plates are stored bare; show them the way they are printed.
String formatPlate(String plate) {
  final bare = plate.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
  if (bare.length == 7) {
    return '${bare.substring(0, 4)} ${bare.substring(4)}';
  }
  return bare;
}
