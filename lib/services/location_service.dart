import 'package:geolocator/geolocator.dart';

enum AuraLocationStatus {
  unknown,
  unavailable,
  denied,
  deniedForever,
  granted,
}

class AuraLocationState {
  final AuraLocationStatus status;
  final Position? position;

  const AuraLocationState({
    required this.status,
    this.position,
  });

  bool get granted => status == AuraLocationStatus.granted && position != null;
}

class LocationService {
  /// La ubicación SÓLO si el permiso ya está dado: nunca muestra el pedido
  /// del sistema. La usa el Inicio; el único lugar que pide permiso es el
  /// mapa, que es donde hace falta (21/9/2026: los testers veían el pedido
  /// dos veces, en una tarjeta del Inicio y otra vez al abrir el mapa).
  Future<AuraLocationState> getLocationSiYaPermitida() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return const AuraLocationState(status: AuraLocationStatus.unknown);
      }
      return await getCurrentLocation();
    } catch (_) {
      return const AuraLocationState(status: AuraLocationStatus.unavailable);
    }
  }

  Future<AuraLocationState> getCurrentLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      return const AuraLocationState(status: AuraLocationStatus.unavailable);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return const AuraLocationState(status: AuraLocationStatus.denied);
    }

    if (permission == LocationPermission.deniedForever) {
      return const AuraLocationState(status: AuraLocationStatus.deniedForever);
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );

    return AuraLocationState(
      status: AuraLocationStatus.granted,
      position: position,
    );
  }
}
