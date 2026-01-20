import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class LiveTrackingPage extends StatefulWidget {
  const LiveTrackingPage({Key? key}) : super(key: key);

  @override
  State<LiveTrackingPage> createState() => _LiveTrackingPageState();
}

class _LiveTrackingPageState extends State<LiveTrackingPage> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;

  Position? _currentPosition;
  final List<LatLng> _pathPoints = [];

  bool _isTracking = false;
  double _speedKmh = 0.0;
  String _mode = 'Unknown';

  // --- Mode detection based on speed ---
  String _detectModeFromSpeed(double speedKmh) {
    if (speedKmh < 3) return 'Stationary';
    if (speedKmh < 7) return 'Walking';
    if (speedKmh < 20) return 'Cycling';
    if (speedKmh < 45) return 'City Vehicle';
    if (speedKmh < 90) return 'Highway Vehicle';
    return 'High Speed';
  }

  @override
  void initState() {
    super.initState();
    _initAndStartTracking();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initAndStartTracking() async {
    // Ask permission & turn on GPS
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable GPS to start live tracking')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission permanently denied. Enable from settings.'),
        ),
      );
      return;
    }

    // Get first fix
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    setState(() {
      _currentPosition = pos;
      _pathPoints.clear();
      _pathPoints.add(LatLng(pos.latitude, pos.longitude));
      _isTracking = true;
    });

    _moveCameraTo(pos);

    // Start stream
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // meters
      ),
    ).listen((position) {
      final double speedKmh = (position.speed) * 3.6; // m/s → km/h
      final String mode = _detectModeFromSpeed(speedKmh);

      setState(() {
        _currentPosition = position;
        _speedKmh = speedKmh;
        _mode = mode;
        _pathPoints.add(LatLng(position.latitude, position.longitude));
      });

      _moveCameraTo(position);
    });
  }

  void _moveCameraTo(Position pos) {
    if (_mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 17,
        ),
      ),
    );
  }

  void _toggleTracking() {
    if (_isTracking) {
      // Stop
      _positionSub?.cancel();
      _positionSub = null;
      setState(() {
        _isTracking = false;
      });
    } else {
      // Restart
      _initAndStartTracking();
    }
  }

  @override
  Widget build(BuildContext context) {
    final LatLng? currentLatLng = _currentPosition == null
        ? null
        : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking'),
      ),
      body: Column(
        children: [
          // Top info card
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x11000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0F2FE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: Color(0xFF2563EB),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isTracking ? 'Tracking in progress' : 'Tracking stopped',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Speed: ${_speedKmh.toStringAsFixed(1)} km/h • Mode: $_mode',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Map
          Expanded(
            child: currentLatLng == null
                ? const Center(
              child: Text(
                'Getting your location...',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            )
                : GoogleMap(
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              mapType: MapType.normal,
              initialCameraPosition: CameraPosition(
                target: currentLatLng,
                zoom: 16,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
              },
              markers: {
                Marker(
                  markerId: const MarkerId('me'),
                  position: currentLatLng,
                  infoWindow: const InfoWindow(title: 'You'),
                ),
              },
              polylines: {
                if (_pathPoints.length > 1)
                  Polyline(
                    polylineId: const PolylineId('path'),
                    points: _pathPoints,
                    width: 4,
                    color: const Color(0xFF2563EB),
                  ),
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleTracking,
        backgroundColor: _isTracking ? Colors.redAccent : const Color(0xFF2563EB),
        icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
        label: Text(_isTracking ? 'Stop' : 'Start'),
      ),
    );
  }
}
