import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class MapRouteResult {
  const MapRouteResult({
    required this.points,
    required this.distanceMeters,
    required this.followsRoads,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final bool followsRoads;
}

class MapRouteService {
  static const _timeout = Duration(seconds: 8);

  static Future<MapRouteResult> fetchRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final directDistance = const Distance().as(
      LengthUnit.Meter,
      origin,
      destination,
    );

    final url = Uri.https(
      'router.project-osrm.org',
      '/route/v1/driving/'
          '${origin.longitude},${origin.latitude};'
          '${destination.longitude},${destination.latitude}',
      {
        'overview': 'full',
        'geometries': 'geojson',
        'alternatives': 'false',
        'steps': 'false',
      },
    );

    try {
      final response = await http.get(url).timeout(_timeout);
      if (response.statusCode != 200) {
        return _directFallback(origin, destination, directDistance);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') {
        return _directFallback(origin, destination, directDistance);
      }

      final routes = data['routes'];
      if (routes is! List || routes.isEmpty) {
        return _directFallback(origin, destination, directDistance);
      }

      final firstRoute = routes.first as Map<String, dynamic>;
      final geometry = firstRoute['geometry'];
      final coordinates = geometry is Map<String, dynamic>
          ? geometry['coordinates']
          : null;
      if (coordinates is! List || coordinates.length < 2) {
        return _directFallback(origin, destination, directDistance);
      }

      final points = <LatLng>[];
      for (final coordinate in coordinates) {
        if (coordinate is List && coordinate.length >= 2) {
          final lng = coordinate[0];
          final lat = coordinate[1];
          if (lat is num && lng is num) {
            points.add(LatLng(lat.toDouble(), lng.toDouble()));
          }
        }
      }

      if (points.length < 2) {
        return _directFallback(origin, destination, directDistance);
      }

      final routedDistance = firstRoute['distance'];
      return MapRouteResult(
        points: points,
        distanceMeters: routedDistance is num
            ? routedDistance.toDouble()
            : directDistance,
        followsRoads: true,
      );
    } catch (_) {
      return _directFallback(origin, destination, directDistance);
    }
  }

  static MapRouteResult _directFallback(
    LatLng origin,
    LatLng destination,
    double distanceMeters,
  ) {
    return MapRouteResult(
      points: [origin, destination],
      distanceMeters: distanceMeters,
      followsRoads: false,
    );
  }
}
