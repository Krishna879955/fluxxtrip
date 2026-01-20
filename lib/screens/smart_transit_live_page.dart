// lib/screens/smart_transit_live_page.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:intl/intl.dart';

// 👉 Put your REAL key here OR import from api_key.dart:
// import 'package:your_app/api_key.dart'; // and use googleMapsApiKey from there
const String googleMapsApiKey = 'AIzaSyCW-Zva23k6-9-BiPvdFiuEZEWhK6ceYFk';

class SmartTransitLivePage extends StatefulWidget {
  const SmartTransitLivePage({Key? key}) : super(key: key);

  @override
  State<SmartTransitLivePage> createState() => _SmartTransitLivePageState();
}

class _SmartTransitLivePageState extends State<SmartTransitLivePage> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;

  Position? _currentPosition;
  LatLng? _destination;

  final List<LatLng> _routePoints = [];
  bool _isFetchingRoute = false;

  String _statusMessage = 'Long-press on the map to select destination.';
  String _routeHeader = '';      // "16.9 km • 1h 53m (Transit)"
  String _routeSubline = '';     // "45 mins in bus • Wait: ~10 mins (7:15 PM)"
  double? _distanceKm;
  double? _estimatedFare;

  final PolylinePoints _polylinePoints = PolylinePoints();

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    // Check service
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please turn on GPS / location services.'),
        ),
      );
      return;
    }

    // Check permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is required for live transit.'),
        ),
      );
      return;
    }

    // Get initial location
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    setState(() => _currentPosition = pos);

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(pos.latitude, pos.longitude),
        15,
      ),
    );

    // Listen to location changes
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((p) {
      setState(() => _currentPosition = p);
    });
  }

  // =====================  ON MAP LONG PRESS  =====================

  Future<void> _onMapLongPress(LatLng dest) async {
    if (_currentPosition == null) {
      setState(() {
        _statusMessage = 'Waiting for your current location...';
      });
      return;
    }

    final origin = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    setState(() {
      _destination = dest;
      _routePoints.clear();
      _routeHeader = '';
      _routeSubline = '';
      _distanceKm = null;
      _estimatedFare = null;
      _statusMessage = 'Finding transit route...';
    });

    await _fetchTransitRoute(origin, dest);
  }

  // =====================  DIRECTIONS (TRANSIT)  =====================

  Future<void> _fetchTransitRoute(LatLng origin, LatLng destination) async {
    setState(() => _isFetchingRoute = true);

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
            '?origin=${origin.latitude},${origin.longitude}'
            '&destination=${destination.latitude},${destination.longitude}'
            '&mode=transit'
            '&departure_time=now'
            '&key=$googleMapsApiKey',
      );

      final resp = await http.get(url);
      if (resp.statusCode != 200) {
        setState(() {
          _statusMessage =
          'Directions HTTP error: ${resp.statusCode} ${resp.reasonPhrase}';
        });
        return;
      }

      final Map<String, dynamic> data = json.decode(resp.body);
      final String status = data['status'] ?? 'UNKNOWN';
      final String errorMessage = data['error_message'] ?? '';

      // 👉 This is where REQUEST_DENIED, ZERO_RESULTS etc. will appear
      if (status != 'OK') {
        setState(() {
          _statusMessage = 'No transit route found ($status'
              '${errorMessage.isNotEmpty ? ': $errorMessage' : ''}).';
          _routeHeader = '';
          _routeSubline = '';
          _routePoints.clear();
          _distanceKm = null;
          _estimatedFare = null;
        });

        // Optional: also show snackbar for visibility
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Directions error: $status'
                    '${errorMessage.isNotEmpty ? ' – $errorMessage' : ''}',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (data['routes'] == null ||
          (data['routes'] as List).isEmpty ||
          data['routes'][0]['legs'] == null ||
          (data['routes'][0]['legs'] as List).isEmpty) {
        setState(() {
          _statusMessage = 'No valid transit leg found.';
        });
        return;
      }

      final route = data['routes'][0];
      final leg = route['legs'][0];

      // Distance / duration text
      final String distanceText = leg['distance']?['text'] ?? '—';
      final String durationText = leg['duration']?['text'] ?? '—';

      // --- decode polyline ---
      final String encodedPolyline =
          route['overview_polyline']?['points'] ?? '';
      final decoded = _polylinePoints.decodePolyline(encodedPolyline);
      final points =
      decoded.map((e) => LatLng(e.latitude, e.longitude)).toList();

      // --- compute bus-only time + waiting time ---
      final List<dynamic> steps = leg['steps'] as List<dynamic>? ?? [];

      int transitSeconds = 0;
      DateTime? firstDepartureLocal;

      for (final step in steps) {
        if (step['travel_mode'] == 'TRANSIT') {
          final dur = step['duration'];
          if (dur != null && dur['value'] != null) {
            transitSeconds += (dur['value'] as num).toInt();
          }

          if (firstDepartureLocal == null) {
            final transitDetails = step['transit_details'];
            if (transitDetails != null &&
                transitDetails['departure_time'] != null &&
                transitDetails['departure_time']['value'] != null) {
              final int depEpoch =
              (transitDetails['departure_time']['value'] as num).toInt();
              // API gives seconds UTC
              firstDepartureLocal = DateTime.fromMillisecondsSinceEpoch(
                depEpoch * 1000,
                isUtc: true,
              ).toLocal();
            }
          }
        }
      }

      final int transitMinutes = (transitSeconds / 60).round();
      String transitLine = transitMinutes > 0
          ? '$transitMinutes mins in bus/metro'
          : 'Transit segment info unavailable';

      String waitPart = '';
      if (firstDepartureLocal != null) {
        final now = DateTime.now();
        final diff = firstDepartureLocal.difference(now);
        if (!diff.isNegative) {
          final waitMins = diff.inMinutes;
          final depStr = DateFormat('h:mm a').format(firstDepartureLocal);
          waitPart = ' • Wait: ~${waitMins} min (depart $depStr)';
        }
      }

      final double rawMeters =
          (leg['distance']?['value'] as num?)?.toDouble() ?? 0.0;
      final double km = rawMeters / 1000.0;
      // simple fare model: ₹7 per km
      final double fare = km * 7.0;

      setState(() {
        _routePoints
          ..clear()
          ..addAll(points);

        _routeHeader = '$distanceText • $durationText (Transit)';
        _routeSubline = '$transitLine$waitPart';
        _distanceKm = double.parse(km.toStringAsFixed(1));
        _estimatedFare = double.parse(fare.toStringAsFixed(0));
        _statusMessage =
        'Route ready — drag / zoom map to explore. Long-press again to change destination.';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Failed to fetch route: $e';
      });
    } finally {
      setState(() => _isFetchingRoute = false);
    }
  }

  // =====================  UI  =====================

  @override
  Widget build(BuildContext context) {
    final LatLng? pos = _currentPosition == null
        ? null
        : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Smart Public Transit'),
      ),
      body: Column(
        children: [
          // Top info card
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x15000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0F2FE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.directions_transit_filled_rounded,
                      size: 22,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _routeHeader.isNotEmpty
                              ? _routeHeader
                              : 'Transit route not selected',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _routeHeader.isNotEmpty
                              ? _routeSubline
                              : 'Long-press anywhere on map to choose your destination.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isFetchingRoute)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),

          // Map
          Expanded(
            child: pos == null
                ? const Center(
              child: Text(
                'Getting your location...',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            )
                : GoogleMap(
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (c) => _mapController = c,
              onLongPress: _onMapLongPress,
              initialCameraPosition:
              CameraPosition(target: pos, zoom: 14.5),
              markers: {
                Marker(
                  markerId: const MarkerId('me'),
                  position: pos,
                  infoWindow: const InfoWindow(title: 'You'),
                ),
                if (_destination != null)
                  Marker(
                    markerId: const MarkerId('dest'),
                    position: _destination!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed,
                    ),
                    infoWindow:
                    const InfoWindow(title: 'Destination'),
                  ),
              },
              polylines: {
                if (_routePoints.length > 1)
                  Polyline(
                    polylineId: const PolylineId('route'),
                    width: 5,
                    color: const Color(0xFF2563EB),
                    points: _routePoints,
                  ),
              },
            ),
          ),

          // Bottom fare bar
          Container(
            width: double.infinity,
            color: Colors.black87,
            padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _routeHeader.isNotEmpty
                      ? _routeHeader
                      : _statusMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_estimatedFare != null && _distanceKm != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Estimated fare: ₹${_estimatedFare!.toStringAsFixed(0)}  •  Distance: ${_distanceKm!.toStringAsFixed(1)} km',
                    style: const TextStyle(
                      color: Color(0xFF4ADE80),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
