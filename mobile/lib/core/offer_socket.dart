import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';

/// The driver's live channel: offers, withdrawals and status changes.
///
/// Push notifications wake the phone; this socket is what keeps an open app
/// current without polling, which matters when an offer expires in 60 seconds.
class OfferSocket {
  OfferSocket(this._readToken);

  final Future<String?> Function() _readToken;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  bool _closed = false;
  int _attempt = 0;

  final _events = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<void> connect() async {
    if (_closed) return;
    final token = await _readToken();
    if (token == null || token.isEmpty) {
      _scheduleRetry();
      return;
    }

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('${AppConfig.wsBaseUrl}/driver?token=${Uri.encodeComponent(token)}'),
      );
      _subscription = _channel!.stream.listen(
        (message) {
          _attempt = 0;
          try {
            final decoded = jsonDecode('$message');
            if (decoded is Map) {
              _events.add(decoded.map((key, value) => MapEntry('$key', value)));
            }
          } on FormatException {
            // A frame we cannot read is not a reason to drop the connection.
          }
        },
        onDone: _scheduleRetry,
        onError: (_) => _scheduleRetry(),
        cancelOnError: true,
      );
    } on Exception {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_closed) return;
    _attempt = _attempt >= 5 ? 5 : _attempt + 1;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: 1 << _attempt), connect);
  }

  Future<void> dispose() async {
    _closed = true;
    _retry?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _events.close();
  }
}
