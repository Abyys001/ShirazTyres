/// Every failure the UI has to render, in one shape.
///
/// The API always answers errors as `{"detail": ..., "errors": {field: [msg]}}`,
/// so field-level messages can be attached to the input that caused them.
class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.fieldErrors = const <String, List<String>>{},
  });

  final String message;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  bool get isUnauthorised => statusCode == 401;
  bool get isThrottled => statusCode == 429;

  String? fieldError(String field) {
    final messages = fieldErrors[field];
    return (messages == null || messages.isEmpty) ? null : messages.first;
  }

  @override
  String toString() => message;
}
