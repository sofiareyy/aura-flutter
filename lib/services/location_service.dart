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
