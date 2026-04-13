import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/estudio.dart';

class NearbyStudyResult {
  final Estudio estudio;
  final LatLng? coordinates;
  final double? distanceKm;

  const NearbyStudyResult({
    required this.estudio,
    required this.coordinates,
    required this.distanceKm,
  });
}

class StudioGeoService {
  static const LatLng defaultCenter = LatLng(-34.6037, -58.3816);

  static const Map<String, LatLng> _knownAreas = {
    'escobar': LatLng(-34.3489, -58.7978),
    'pilar': LatLng(-34.4587, -58.9142),
    'palermo': LatLng(-34.5875, -58.4200),
    'recoleta': LatLng(-34.5889, -58.3974),
    'belgrano': LatLng(-34.5621, -58.4562),
    'nordelta': LatLng(-34.4016, -58.6481),
    'tigre': LatLng(-34.4260, -58.5796),
    'san isidro': LatLng(-34.4721, -58.5136),
    'vicente lopez': LatLng(-34.5263, -58.4800),
    'puerto madero': LatLng(-34.6118, -58.3623),
    'caballito': LatLng(-34.6186, -58.4421),
    'villa crespo': LatLng(-34.5995, -58.4371),
    'nuñez': LatLng(-34.5453, -58.4662),
    'martinez': LatLng(-34.4920, -58.4997),
    'olivos': LatLng(-34.5071, -58.4870),
    'buenos aires': LatLng(-34.6037, -58.3816),
    'caba': LatLng(-34.6037, -58.3816),
  };

  LatLng estimateCoordinates(Estudio estudio) {
    if (estudio.lat != null && estudio.lng != null) {
      return LatLng(estudio.lat!, estudio.lng!);
    }
    final baseText =
        '${estudio.barrio ?? ''} ${estudio.direccion ?? ''} ${estudio.nombre}'
            .toLowerCase();
    LatLng base = defaultCenter;

    for (final entry in _knownAreas.entries) {
      if (baseText.contains(entry.key)) {
        base = entry.value;
        break;
      }
    }

    final seed = ((estudio.id ?? estudio.nombre.hashCode) & 0x7fffffff);
    final latOffset = ((seed % 17) - 8) * 0.0022;
    final lngOffset = (((seed ~/ 17) % 17) - 8) * 0.0026;
    return LatLng(base.latitude + latOffset, base.longitude + lngOffset);
  }

  List<NearbyStudyResult> sortByDistance(
    List<Estudio> estudios,
    Position? userPosition,
  ) {
    final results = estudios.map((estudio) {
      final point = estimateCoordinates(estudio);
      final hasRealCoordinates = estudio.lat != null && estudio.lng != null;
      final distanceKm = userPosition == null
          ? null
          : !hasRealCoordinates
          ? null
          : Geolocator.distanceBetween(
                userPosition.latitude,
                userPosition.longitude,
                point.latitude,
                point.longitude,
              ) /
              1000;
      return NearbyStudyResult(
        estudio: estudio,
        coordinates: point,
        distanceKm: distanceKm,
      );
    }).toList();

    results.sort((a, b) {
      final aDistance = a.distanceKm;
      final bDistance = b.distanceKm;
      if (aDistance == null && bDistance == null) {
        return a.estudio.nombre.compareTo(b.estudio.nombre);
      }
      if (aDistance == null) return 1;
      if (bDistance == null) return -1;
      return aDistance.compareTo(bDistance);
    });

    return results;
  }

  LatLng centerForResults(List<NearbyStudyResult> studies, Position? userPosition) {
    if (userPosition != null) {
      return LatLng(userPosition.latitude, userPosition.longitude);
    }
    if (studies.isNotEmpty && studies.first.coordinates != null) {
      return studies.first.coordinates!;
    }
    return defaultCenter;
  }

  String formatDistance(double? distanceKm) {
    if (distanceKm == null) return 'Explorá en mapa';
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()} m';
    }
    return '${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)} km';
  }
}
