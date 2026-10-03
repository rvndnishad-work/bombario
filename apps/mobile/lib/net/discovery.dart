import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

/// Bonjour / mDNS service type rooms announce on the local network.
const roomServiceType = '_bombario._tcp';

/// Announces a hosted room so phones on the same Wi-Fi list it in Join.
class RoomBroadcast {
  RoomBroadcast({required this.code, required this.port});

  final String code;
  final int port;
  BonsoirBroadcast? _broadcast;

  Future<void> start() async {
    try {
      final broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: 'Bombario $code',
          type: roomServiceType,
          port: port,
          attributes: {'code': code},
        ),
      );
      await broadcast.initialize();
      await broadcast.start();
      _broadcast = broadcast;
    } catch (e) {
      // Discovery is a convenience; the room still works by typed address.
      debugPrint('Room broadcast unavailable: $e');
    }
  }

  Future<void> stop() async {
    await _broadcast?.stop();
    _broadcast = null;
  }
}

/// A room seen on the local network.
class DiscoveredRoom {
  const DiscoveredRoom({
    required this.name,
    required this.code,
    required this.host,
    required this.port,
  });

  final String name;
  final String code;
  final String host;
  final int port;
}

/// Lists rooms announced with [RoomBroadcast].
class RoomDiscovery extends ChangeNotifier {
  final Map<String, DiscoveredRoom> _rooms = {};
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  String? error;

  List<DiscoveredRoom> get rooms => _rooms.values.toList();

  Future<void> start() async {
    try {
      final discovery = BonsoirDiscovery(type: roomServiceType);
      await discovery.initialize();
      _sub = discovery.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            // Found services carry no address until resolved.
            discovery.serviceResolver.resolveService(event.service);
          case BonsoirDiscoveryServiceResolvedEvent():
            _add(event.service);
          case BonsoirDiscoveryServiceUpdatedEvent():
            _add(event.service);
          case BonsoirDiscoveryServiceLostEvent():
            _rooms.remove(event.service.name);
            notifyListeners();
          default:
            break;
        }
      });
      await discovery.start();
      _discovery = discovery;
    } catch (e) {
      error = 'Room discovery unavailable: $e';
      notifyListeners();
    }
  }

  void _add(BonsoirService service) {
    final host = service.hostAddress ?? service.hostname;
    if (host == null) return;
    _rooms[service.name] = DiscoveredRoom(
      name: service.name,
      code: service.attributes['code'] ?? '',
      host: host,
      port: service.port,
    );
    notifyListeners();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    await _discovery?.stop();
    _discovery = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
