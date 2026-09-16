import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';

/// How often to prove the connection is still there. Mobile networks and
/// proxies drop an idle socket silently: nothing arrives, nothing errors, and
/// the app waits for offers that are being delivered to a dead pipe.
const _pingInterval = Duration(seconds: 25);

/// How long to wait for the answering pong before treating the socket as gone.
const _pongTimeout = Duration(seconds: 10);

/// The driver's live channel: offers, withdrawals and status changes.
///
/// Push notifications wake the phone; this socket is what keeps an open app
/// current without polling, which matters when an offer expires in 60 seconds.
class OfferSocket {
  OfferSocket(this._readToken, {Future<void> Function()? onRefused})
      : _onRefused = onRefused;

  final Future<String?> Function() _readToken;

  /// Called when the server refuses the handshake, before the next attempt.
  /// Renewing the access token is the only thing that fixes that case, and only
  /// the REST client knows how.
  final Future<void> Function()? _onRefused;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  Timer? _ping;
  Timer? _pongWatchdog;
  bool _closed = false;
  int _attempt = 0;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get events => _events.stream;

  /// Whether the live channel is up. A screen that knows it is not can poll
  /// harder and say so, rather than showing stale state as though it were live.
  Stream<bool> get connection => _connected.stream;

  bool _isConnected = false;

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_closed) return;

    // Anything left from a previous attempt goes first. Overwriting the channel
    // without cancelling its subscription left the old socket delivering into
    // the same controller, so one event arrived two or three times and every
    // dead connection kept its own reconnect running.
    await _teardown();

    final token = await _readToken();
    if (token == null || token.isEmpty) {
      _scheduleRetry();
      return;
    }

    final channel = WebSocketChannel.connect(
      Uri.parse('${AppConfig.wsBaseUrl}/driver?token=${Uri.encodeComponent(token)}'),
    );

    try {
      // Without this the failed upgrade surfaces as an unhandled error on the
      // sink rather than on the stream, and brings the whole zone down with it.
      // Awaiting it turns a refused handshake into an ordinary retry.
      await channel.ready;
    } catch (_) {
      await _discard(channel);
      // A refused handshake is nearly always an access token that expired while
      // the app was in the background. Retrying the dead token forever is how a
      // technician stops being offered work without anything looking broken, so
      // the REST client is asked to renew before the next attempt.
      await _refreshQuietly();
      _scheduleRetry();
      return;
    }

    if (_closed) {
      await _discard(channel);
      return;
    }

    _channel = channel;
    _subscription = channel.stream.listen(
      _onFrame,
      onDone: _scheduleRetry,
      onError: (_) => _scheduleRetry(),
      cancelOnError: true,
    );
    _setConnected(true);
    _startPinging();
  }

  Future<void> _refreshQuietly() async {
    try {
      await _onRefused?.call();
    } catch (_) {
      // Whatever went wrong renewing, the retry below is still the right move.
    }
  }

  Future<void> _discard(WebSocketChannel channel) async {
    try {
      await channel.sink.close();
    } catch (_) {
      // Closing a socket that never opened is not a failure.
    }
  }

  void _onFrame(dynamic message) {
    _attempt = 0;
    _pongWatchdog?.cancel();
    _pongWatchdog = null;
    _setConnected(true);

    try {
      final decoded = jsonDecode('$message');
      if (decoded is! Map) return;
      final event = decoded.map((key, value) => MapEntry('$key', value));
      // The keepalive's own answer is not news for anybody upstream.
      if (event['event'] == 'pong') return;
      _events.add(event);
    } on FormatException {
      // A frame we cannot read is not a reason to drop the connection.
    }
  }

  void _startPinging() {
    _ping?.cancel();
    _ping = Timer.periodic(_pingInterval, (_) {
      final channel = _channel;
      if (channel == null) return;
      try {
        channel.sink.add('ping');
      } catch (_) {
        _scheduleRetry();
        return;
      }
      // Silence after a ping is the one reliable sign of a half-open socket.
      _pongWatchdog?.cancel();
      _pongWatchdog = Timer(_pongTimeout, _scheduleRetry);
    });
  }

  void _setConnected(bool value) {
    if (_isConnected == value || _closed) return;
    _isConnected = value;
    _connected.add(value);
  }

  Future<void> _teardown() async {
    _ping?.cancel();
    _ping = null;
    _pongWatchdog?.cancel();
    _pongWatchdog = null;
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    await subscription?.cancel();
    try {
      await channel?.sink.close();
    } catch (_) {
      // Closing a socket that is already gone is not a failure.
    }
    _setConnected(false);
  }

  void _scheduleRetry() {
    if (_closed || _retry != null) return;
    _setConnected(false);
    _attempt = _attempt >= 5 ? 5 : _attempt + 1;
    _retry = Timer(Duration(seconds: 1 << _attempt), () {
      _retry = null;
      unawaited(connect());
    });
  }

  Future<void> dispose() async {
    _closed = true;
    _retry?.cancel();
    _retry = null;
    await _teardown();
    await _events.close();
    await _connected.close();
  }
}
