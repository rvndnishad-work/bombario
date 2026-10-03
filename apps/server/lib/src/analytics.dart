import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// Why an analytics batch was refused.
class EventsRejected implements Exception {
  EventsRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A minimal analytics sink: the app posts small batches of named events
/// and they are appended, one JSON object per line, to
/// `<dataDir>/events-YYYY-MM-DD.jsonl` (UTC day of receipt). Without a
/// [dataDir] the latest [ringSize] events are kept in memory.
///
/// Stores only what the app sends plus the receipt time: no IP addresses or
/// other request data.
class Analytics {
  Analytics({this.dataDir, this.ringSize = 1000});

  final String? dataDir;
  final int ringSize;

  static const int maxEvents = 50;
  static const int maxPropsBytes = 2048;
  static final namePattern = RegExp(r'^[a-z0-9_]{1,40}$');

  final Queue<Map<String, dynamic>> _ring = Queue();
  Future<void> _writing = Future.value();

  /// Events held in memory (only without a data directory).
  List<Map<String, dynamic>> get recent => List.unmodifiable(_ring);

  /// Checks a batch and returns the cleaned events. Throws
  /// [EventsRejected] when anything in it is off; nothing is stored then.
  static List<Map<String, dynamic>> validate(Object? body) {
    if (body is! Map || body['events'] is! List) {
      throw EventsRejected('expected {"events": [...]}');
    }
    final events = body['events'] as List;
    if (events.isEmpty || events.length > maxEvents) {
      throw EventsRejected('send 1-$maxEvents events');
    }
    final out = <Map<String, dynamic>>[];
    for (final e in events) {
      if (e is! Map) throw EventsRejected('events must be objects');
      final name = e['name'];
      if (name is! String || !namePattern.hasMatch(name)) {
        throw EventsRejected('bad event name');
      }
      final ts = e['ts'];
      if (ts is! int || ts < 0) throw EventsRejected('ts must be epoch ms');
      final props = e['props'] ?? const <String, dynamic>{};
      if (props is! Map) throw EventsRejected('props must be an object');
      for (final v in props.values) {
        if (v != null && v is! String && v is! num && v is! bool) {
          throw EventsRejected('props must be flat');
        }
      }
      if (utf8.encode(jsonEncode(props)).length > maxPropsBytes) {
        throw EventsRejected('props over $maxPropsBytes bytes');
      }
      out.add({'name': name, 'ts': ts, 'props': props});
    }
    return out;
  }

  /// Stores a validated batch.
  Future<void> record(List<Map<String, dynamic>> events) {
    final now = DateTime.now().toUtc();
    final stamped = [
      for (final e in events) {...e, 'rx': now.millisecondsSinceEpoch},
    ];
    final dir = dataDir;
    if (dir == null) {
      _ring.addAll(stamped);
      while (_ring.length > ringSize) {
        _ring.removeFirst();
      }
      return Future.value();
    }
    final day = now.toIso8601String().substring(0, 10);
    final file = File('$dir/events-$day.jsonl');
    final lines = stamped.map((e) => '${jsonEncode(e)}\n').join();
    return _writing = _writing.then((_) async {
      await file.parent.create(recursive: true);
      await file.writeAsString(lines, mode: FileMode.append, flush: true);
    }).catchError((Object e) {
      stderr.writeln('events not saved: $e');
    });
  }

  Future<void> flush() => _writing;
}
