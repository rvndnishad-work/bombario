import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'online.dart';

/// Anonymous gameplay analytics (§13): which stages people clear, where
/// they quit, how long matches last. Events carry a random install id and
/// game facts only, never names or contacts.
///
/// Events queue in memory and go to the room server's `POST /events` in
/// batches; a failed upload stays queued for the next flush, and the
/// oldest events drop once [maxQueue] is reached. Nothing is sent while [enabled] is false (the Settings switch)
/// or under `flutter test`.
class Analytics {
  Analytics._();

  static final Analytics instance = Analytics._();

  static const int batchSize = 20;
  static const int maxQueue = 200;
  static const Duration flushEvery = Duration(seconds: 30);

  bool enabled = true;

  /// Set per install by [start]; anonymous.
  String installId = '';

  final List<Map<String, Object?>> _queue = [];
  Timer? _timer;
  bool _sending = false;

  /// Uploads go through this; replaced in tests.
  @visibleForTesting
  Future<bool> Function(List<Map<String, Object?>> events) sender = (events) =>
      OnlineServer.sendEvents(
        OnlineServer.parse(OnlineServer.url.value),
        events,
      );

  static final bool _underTest =
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// Events waiting to upload, oldest first.
  List<Map<String, Object?>> get pending => List.unmodifiable(_queue);

  void start({required String installId}) {
    this.installId = installId;
    _timer?.cancel();
    if (!_underTest) {
      _timer = Timer.periodic(flushEvery, (_) => flush());
    }
    log('app_open');
  }

  /// Records [name] (`snake_case`) with flat [props].
  void log(String name, [Map<String, Object?> props = const {}]) {
    if (!enabled) return;
    _queue.add({
      'name': name,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'props': {'install': installId, ...props},
    });
    if (_queue.length > maxQueue) {
      _queue.removeRange(0, _queue.length - maxQueue);
    }
    if (_queue.length >= batchSize && !_underTest) flush();
  }

  /// Sends what is queued, up to 50 per request (the server's limit).
  Future<void> flush() async {
    if (_sending || _queue.isEmpty || !enabled) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(50).toList();
        bool ok;
        try {
          ok = await sender(batch);
        } catch (_) {
          ok = false;
        }
        if (!ok) break;
        _queue.removeRange(0, batch.length);
      }
    } finally {
      _sending = false;
    }
  }

  /// Turns sharing on or off; switching off drops anything queued.
  void setEnabled(bool on) {
    enabled = on;
    if (!on) _queue.clear();
  }
}
