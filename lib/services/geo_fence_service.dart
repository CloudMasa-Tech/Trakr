import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';

class GeoFenceService {
  GeoFenceService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _db => _context.firestore;
  static const double temporaryGpsJitterGraceMetres = 25;

  static bool isValidLatitude(double value) => value >= -90 && value <= 90;

  static bool isValidLongitude(double value) => value >= -180 && value <= 180;

  static bool isValidRadius(double value) => value >= 10 && value <= 10000;

  static double effectiveDistance({
    required double distanceMetres,
    required double accuracyMetres,
  }) {
    final distance =
        distanceMetres.isFinite && distanceMetres > 0 ? distanceMetres : 0.0;
    final accuracy =
        accuracyMetres.isFinite && accuracyMetres > 0 ? accuracyMetres : 0.0;
    return (distance - accuracy).clamp(0.0, double.infinity);
  }

  static double validationRadius({
    required double radiusMetres,
  }) {
    final radius =
        radiusMetres.isFinite && radiusMetres > 0 ? radiusMetres : 50.0;
    return radius + temporaryGpsJitterGraceMetres;
  }

  static double recommendedRadiusForScan({
    required double distanceMetres,
    required double accuracyMetres,
    double safetyMarginMetres = 10,
  }) {
    final distance =
        distanceMetres.isFinite && distanceMetres > 0 ? distanceMetres : 0.0;
    final accuracy =
        accuracyMetres.isFinite && accuracyMetres > 0 ? accuracyMetres : 0.0;
    final margin = safetyMarginMetres.isFinite && safetyMarginMetres > 0
        ? safetyMarginMetres
        : 0.0;
    final requiredRadius = distance + accuracy + margin;
    return (requiredRadius / 10).ceil() * 10;
  }

  static double suggestedOfficeRadius({
    double? south,
    double? north,
    double? west,
    double? east,
    double fallbackMetres = 140,
  }) {
    if (south == null || north == null || west == null || east == null) {
      return fallbackMetres;
    }
    if (![south, north, west, east].every((value) => value.isFinite)) {
      return fallbackMetres;
    }

    final centerLat = (south + north) / 2;
    final centerLng = (west + east) / 2;
    final cornerDistance = Geolocator.distanceBetween(
      centerLat,
      centerLng,
      north,
      east,
    );
    if (!cornerDistance.isFinite || cornerDistance <= 0) {
      return fallbackMetres;
    }

    final suggested = ((cornerDistance + 25) / 10).ceil() * 10;
    return suggested.clamp(50, 250).toDouble();
  }

  static double zoomForRadius(double radius) {
    if (radius <= 75) return 18;
    if (radius <= 150) return 17;
    if (radius <= 300) return 16;
    if (radius <= 700) return 15;
    if (radius <= 1500) return 14;
    if (radius <= 3000) return 13;
    return 12;
  }

  Future<GeoLocationSearchResult?> searchLocation(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    Object? lastError;

    for (final candidate in _locationSearchCandidates(trimmed)) {
      try {
        final nominatimResult = await _searchNominatim(candidate);
        if (nominatimResult != null) return nominatimResult;
      } catch (error) {
        lastError = error;
      }

      try {
        final photonResult = await _searchPhoton(candidate);
        if (photonResult != null) return photonResult;
      } catch (error) {
        lastError = error;
      }

      try {
        final openMeteoResult = await _searchOpenMeteo(candidate);
        if (openMeteoResult != null) return openMeteoResult;
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) {
      throw Exception(
        'Location search service is unavailable. Check internet/CORS access and try again.',
      );
    }

    return null;
  }

  List<String> _locationSearchCandidates(String query) {
    final normalized = query.replaceAll(RegExp(r'\s+'), ' ').trim();
    final cleaned = normalized
        .replaceAll(RegExp(r'\b(in|near|at)\b', caseSensitive: false), ',')
        .replaceAll(RegExp(r',+'), ',')
        .replaceAll(RegExp(r'\s*,\s*'), ', ')
        .trim();
    final businessNameExpanded = normalized
        .replaceAll(RegExp(r'\bpvt\.?\b', caseSensitive: false), 'private')
        .replaceAll(RegExp(r'\bltd\.?\b', caseSensitive: false), 'limited')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final candidates = <String>[
      normalized,
      cleaned,
      businessNameExpanded,
    ];

    final locationWords = <String>[];
    final locationTail = RegExp(
      r'\b(?:in|near|at)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(query);
    final tail = locationTail?.group(1)?.trim();
    if (tail != null && tail.isNotEmpty) {
      candidates.add(tail);
      locationWords.addAll(_significantLocationWords(tail));
    }

    final withoutCommonJoiners = query
        .replaceAll(RegExp(r'\b(in|near|at)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (withoutCommonJoiners.isNotEmpty) {
      candidates.add(withoutCommonJoiners);
    }

    final commaParts = cleaned
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (commaParts.length > 1) {
      candidates.add(commaParts.sublist(1).join(', '));
      locationWords.addAll(_significantLocationWords(commaParts.last));
    }

    final allWords = _significantLocationWords(normalized);
    if (allWords.length >= 2) {
      candidates.add(allWords.sublist(allWords.length - 2).join(' '));
    }
    if (allWords.isNotEmpty) {
      candidates.add(allWords.last);
    }

    for (final word in locationWords) {
      candidates.add(word);
    }

    final seen = <String>{};
    return candidates
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .where((value) => seen.add(value.toLowerCase()))
        .toList();
  }

  List<String> _significantLocationWords(String value) {
    const ignored = {
      'the',
      'a',
      'an',
      'company',
      'office',
      'private',
      'limited',
      'pvt',
      'ltd',
      'llc',
      'inc',
      'corp',
      'corporation',
    };
    return value
        .replaceAll(RegExp(r'[^A-Za-z0-9\s-]'), ' ')
        .split(RegExp(r'\s+'))
        .map((word) => word.trim())
        .where((word) => word.length > 2)
        .where((word) => !ignored.contains(word.toLowerCase()))
        .toList();
  }

  Future<GeoLocationSearchResult?> _searchNominatim(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '1',
      'addressdetails': '1',
    });

    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'qr-attendance-system/1.0',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Location search failed. Please try again.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) return null;

    final first = decoded.first;
    if (first is! Map<String, dynamic>) return null;

    final lat = double.tryParse(first['lat']?.toString() ?? '');
    final lng = double.tryParse(first['lon']?.toString() ?? '');
    if (lat == null || lng == null) return null;

    return GeoLocationSearchResult(
      latitude: lat,
      longitude: lng,
      displayName: first['display_name']?.toString() ?? query,
      suggestedRadiusMetres: _suggestedRadiusFromNominatim(first),
    );
  }

  double _suggestedRadiusFromNominatim(Map<String, dynamic> data) {
    final box = data['boundingbox'];
    if (box is! List || box.length < 4) return 140;
    final south = double.tryParse(box[0]?.toString() ?? '');
    final north = double.tryParse(box[1]?.toString() ?? '');
    final west = double.tryParse(box[2]?.toString() ?? '');
    final east = double.tryParse(box[3]?.toString() ?? '');
    return suggestedOfficeRadius(
      south: south,
      north: north,
      west: west,
      east: east,
    );
  }

  Future<GeoLocationSearchResult?> _searchPhoton(String query) async {
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': query,
      'limit': '1',
      'lang': 'en',
    });

    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'qr-attendance-system/1.0',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final features = decoded['features'];
    if (features is! List || features.isEmpty) return null;

    final first = features.first;
    if (first is! Map<String, dynamic>) return null;
    final geometry = first['geometry'];
    if (geometry is! Map<String, dynamic>) return null;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length < 2) return null;

    final lng = (coordinates[0] as num?)?.toDouble();
    final lat = (coordinates[1] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final properties = first['properties'];
    final displayName = properties is Map<String, dynamic>
        ? [
            properties['name'],
            properties['street'],
            properties['city'],
            properties['state'],
            properties['country'],
          ]
            .where((value) => value != null)
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .join(', ')
        : query;

    return GeoLocationSearchResult(
      latitude: lat,
      longitude: lng,
      displayName: displayName.isEmpty ? query : displayName,
      suggestedRadiusMetres: _suggestedRadiusFromPhoton(properties),
    );
  }

  double _suggestedRadiusFromPhoton(Object? properties) {
    if (properties is! Map<String, dynamic>) return 140;
    final extent = properties['extent'];
    if (extent is! List || extent.length < 4) return 140;
    final west = (extent[0] as num?)?.toDouble();
    final north = (extent[1] as num?)?.toDouble();
    final east = (extent[2] as num?)?.toDouble();
    final south = (extent[3] as num?)?.toDouble();
    return suggestedOfficeRadius(
      south: south,
      north: north,
      west: west,
      east: east,
    );
  }

  Future<GeoLocationSearchResult?> _searchOpenMeteo(String query) async {
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query,
      'count': '1',
      'language': 'en',
      'format': 'json',
    });

    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'qr-attendance-system/1.0',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final results = decoded['results'];
    if (results is! List || results.isEmpty) return null;

    final first = results.first;
    if (first is! Map<String, dynamic>) return null;
    final lat = (first['latitude'] as num?)?.toDouble();
    final lng = (first['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final displayName = [
      first['name'],
      first['admin1'],
      first['country'],
    ]
        .where((value) => value != null)
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .join(', ');

    return GeoLocationSearchResult(
      latitude: lat,
      longitude: lng,
      displayName: displayName.isEmpty ? query : displayName,
      suggestedRadiusMetres: 140,
    );
  }

  Future<LocationAccessResult> ensureLocationAccess() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationAccessResult(
          granted: false,
          status: LocationAccessStatus.serviceDisabled,
          message:
              'Location services are turned off. Please enable GPS/location and try again.',
        );
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.denied) {
        return const LocationAccessResult(
          granted: false,
          status: LocationAccessStatus.denied,
          message:
              'Location permission was denied. Please allow location access to continue.',
        );
      }

      if (perm == LocationPermission.deniedForever) {
        return const LocationAccessResult(
          granted: false,
          status: LocationAccessStatus.deniedForever,
          message:
              'Location permission is permanently denied. Enable it from app settings and try again.',
        );
      }

      return const LocationAccessResult(
        granted: true,
        status: LocationAccessStatus.granted,
        message: 'Location access granted.',
      );
    } catch (error) {
      return LocationAccessResult(
        granted: false,
        status: LocationAccessStatus.error,
        message: 'Unable to access location settings: $error',
      );
    }
  }

  Future<bool> requestPermission() async {
    final result = await ensureLocationAccess();
    return result.granted;
  }

  Future<Position?> getCurrentPosition() async {
    final access = await ensureLocationAccess();
    if (!access.granted) return null;

    Position? bestPosition;

    try {
      bestPosition = await Geolocator.getLastKnownPosition();
    } catch (_) {
      // Fall through to fresh reads below.
    }

    for (final accuracy in const [
      LocationAccuracy.best,
      LocationAccuracy.high,
    ]) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: accuracy,
            timeLimit: const Duration(seconds: 8),
          ),
        );
        bestPosition = _pickMoreAccurate(bestPosition, position);

        if ((bestPosition.accuracy).isFinite && bestPosition.accuracy <= 25) {
          break;
        }
      } catch (_) {
        // Keep the best successful reading we already have.
      }
    }

    return bestPosition;
  }

  Position _pickMoreAccurate(Position? current, Position candidate) {
    if (current == null) return candidate;
    if (!candidate.accuracy.isFinite || candidate.accuracy <= 0) return current;
    if (!current.accuracy.isFinite || current.accuracy <= 0) return candidate;
    return candidate.accuracy < current.accuracy ? candidate : current;
  }

  Future<GeoFenceResult> checkGeoFence(String officeId) async {
    final pos = await getCurrentPosition();
    if (pos == null) {
      return GeoFenceResult(isInside: false, message: 'Permission denied');
    }
    final doc = await _db.collection('offices').doc(officeId).get();
    if (!doc.exists) {
      return GeoFenceResult(isInside: false, message: 'Office not found');
    }
    final d = doc.data()!;
    final oLat = (d['latitude'] as num).toDouble();
    final oLng = (d['longitude'] as num).toDouble();
    final radius = (d['geoFenceRadius'] as num?)?.toDouble() ?? 50;
    final dist =
        Geolocator.distanceBetween(pos.latitude, pos.longitude, oLat, oLng);
    return GeoFenceResult(
      isInside: dist <= radius,
      distance: dist,
      radius: radius,
      userLat: pos.latitude,
      userLng: pos.longitude,
      message: dist <= radius
          ? 'Within geo-fence'
          : 'Outside geo-fence (${dist.round()}m)',
    );
  }
}

class GeoLocationSearchResult {
  final double latitude;
  final double longitude;
  final String displayName;
  final double suggestedRadiusMetres;

  const GeoLocationSearchResult({
    required this.latitude,
    required this.longitude,
    required this.displayName,
    required this.suggestedRadiusMetres,
  });
}

enum LocationAccessStatus {
  granted,
  serviceDisabled,
  denied,
  deniedForever,
  error,
}

class LocationAccessResult {
  final bool granted;
  final LocationAccessStatus status;
  final String message;

  const LocationAccessResult({
    required this.granted,
    required this.status,
    required this.message,
  });
}

class GeoFenceResult {
  final bool isInside;
  final double? distance, radius, userLat, userLng;
  final String message;
  GeoFenceResult({
    required this.isInside,
    this.distance,
    this.radius,
    this.userLat,
    this.userLng,
    required this.message,
  });
}
