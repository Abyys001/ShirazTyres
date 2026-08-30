import 'json.dart';

class Paginated<T> {
  const Paginated({required this.count, required this.results, required this.next});

  factory Paginated.fromJson(dynamic json, T Function(Map<String, dynamic>) parse) {
    // Pagination can be switched off per-view; tolerate a bare list too.
    if (json is List) {
      return Paginated<T>(
        count: json.length,
        results: json.map((item) => parse(asMap(item))).toList(),
        next: '',
      );
    }
    final map = asMap(json);
    final results = map['results'];
    return Paginated<T>(
      count: asInt(map['count']),
      results: results is List
          ? results.map((item) => parse(asMap(item))).toList()
          : <T>[],
      next: asString(map['next']),
    );
  }

  final int count;
  final List<T> results;
  final String next;

  bool get hasMore => next.isNotEmpty;
}
