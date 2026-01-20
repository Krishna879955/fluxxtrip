import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;

/// Single companion form data (with controllers)
class _CompanionEntry {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController ageController = TextEditingController();
  final TextEditingController relationController = TextEditingController();
  String gender = 'Male';

  void dispose() {
    emailController.dispose();
    ageController.dispose();
    relationController.dispose();
  }

  Map<String, dynamic> toMap() {
    return {
      'name': '', // optional – kept for compatibility
      'email': emailController.text.trim(),
      'age': ageController.text.trim(),
      'gender': gender,
      'relation': relationController.text.trim(),
    };
  }
}

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

  // --- Speed smoothing + mode hysteresis ---
  final List<double> _speedSamples = [];
  static const int _maxSpeedSamples = 8; // how many recent speeds to average

  String _pendingMode = 'Unknown';
  int _pendingModeCount = 0;
  static const int _minSamplesForModeSwitch = 3; // need 3 same readings before switching mode

  // origin, destination & distance
  LatLng? _origin; // first point of trip
  LatLng? _destination; // last point of trip
  double _totalDistanceKm = 0.0; // cumulative distance along path

  // --- Extra UI state for signal + destination info ---
  String _trafficSignalHint = 'Normal flow';

  // Detected place info (near destination / current path)
  String _placeName = 'Detecting place...';
  String _placeCategory = 'General area';
  String _distanceCategory = 'Nearby / Local';

  String? _lastNotifiedMode;
  String? _lastNotifiedTrafficHint;
  String? _lastNotifiedPlaceName;

  LatLng? _lastPlaceLookupPoint;

  // --- Trip summary extras ---
  DateTime? _tripStartTime;
  DateTime? _tripEndTime;
  double _maxSpeedKmh = 0.0;
  final Set<String> _modesUsed = {};

  // --- Companions (user editable) ---
  final List<_CompanionEntry> _companions = [];

  // --- Tuning constants for filtering ---
  static const double _minMovementMeters = 15; // ignore moves smaller than this
  static const double _maxAccuracyMeters = 25; // ignore very inaccurate fixes
  static const double _minMovementSpeedKmh = 0.5; // treat slower as stationary

  // Throttle reverse geocoding calls
  static const double _minPlaceLookupDistanceMeters = 200;

  // approximate cost per km based on detected mode
  static const Map<String, double> _modeCostPerKm = {
    'Stationary': 0.0,
    'Walking': 0.0,
    'Cycling': 2.0,
    'City Vehicle': 12.0,
    'Highway Vehicle': 10.0,
    'High Speed': 10.0,
    'Unknown': 10.0,
  };

  Map<String, dynamic> _computeCostSummary() {
    final double distance = _totalDistanceKm;
    // total persons = you + companions
    final int numPersons = 1 + _companions.length;
    final double costPerKm = _modeCostPerKm[_mode] ?? 10.0;

    final double perPerson = (distance * costPerKm).roundToDouble();
    final double total = (perPerson * numPersons).roundToDouble();

    final double minPerPerson = (perPerson * 0.9).roundToDouble();
    final double maxPerPerson = (perPerson * 1.1).roundToDouble();
    final double minTotal = (minPerPerson * numPersons).roundToDouble();
    final double maxTotal = (maxPerPerson * numPersons).roundToDouble();

    return {
      // "numCompanions" here actually means number of persons for cost
      'numCompanions': numPersons,
      'costPerKm': costPerKm,
      'costPerPerson': perPerson,
      'totalCost': total,
      'minPerPerson': minPerPerson,
      'maxPerPerson': maxPerPerson,
      'minTotalCost': minTotal,
      'maxTotalCost': maxTotal,
    };
  }

  // --- Mode detection based on speed ---
  String _detectModeFromSpeed(double speedKmh) {
    if (speedKmh < 1.0) return 'Stationary'; // < 1 km/h
    if (speedKmh < 8.0) return 'Walking'; // 1–8 km/h
    if (speedKmh < 20) return 'Cycling';
    if (speedKmh < 45) return 'City Vehicle';
    if (speedKmh < 90) return 'Highway Vehicle';
    return 'High Speed';
  }

  // --- Simple "traffic / signal" hint based on speed ---
  String _computeTrafficSignalHint(double speedKmh) {
    if (speedKmh < 3) {
      return 'Stopped • possible signal / congestion';
    } else if (speedKmh < 15) {
      return 'Slow traffic • near junction / signal';
    } else if (speedKmh < 45) {
      return 'City traffic • frequent signals likely';
    } else {
      return 'Free flow • fewer signals';
    }
  }

  // --- Distance-based trip type ---
  String _computeDistanceCategory(double distanceKm) {
    if (distanceKm >= 50) {
      return 'Outstation / Long trip';
    } else if (distanceKm >= 20) {
      return 'City tour / long commute';
    } else if (distanceKm >= 5) {
      return 'Urban commute';
    } else {
      return 'Nearby / Local';
    }
  }

  // --- Place-type classifier based on text keywords ---
  String _classifyPlaceCategory(String text) {
    final lower = text.toLowerCase();

    // Tourist / attractions
    if (lower.contains('fort') ||
        lower.contains('palace') ||
        lower.contains('museum') ||
        lower.contains('beach') ||
        lower.contains('waterfall') ||
        lower.contains('dam') ||
        lower.contains('lake') ||
        lower.contains('park') ||
        lower.contains('garden') ||
        lower.contains('zoo') ||
        lower.contains('view point') ||
        lower.contains('tourist') ||
        lower.contains('statue')) {
      return 'Tourist attraction';
    }

    // Religious
    if (lower.contains('temple') ||
        lower.contains('mandir') ||
        lower.contains('masjid') ||
        lower.contains('mosque') ||
        lower.contains('church') ||
        lower.contains('gurudwara') ||
        lower.contains('dargah')) {
      return 'Religious / Pilgrimage';
    }

    // Transit
    if (lower.contains('railway') ||
        lower.contains('station') ||
        lower.contains('metro') ||
        lower.contains('bus stand') ||
        lower.contains('bus stop') ||
        lower.contains('isbt') ||
        lower.contains('airport') ||
        lower.contains('terminal') ||
        lower.contains('depot')) {
      return 'Transit hub';
    }

    // Education
    if (lower.contains('school') ||
        lower.contains('college') ||
        lower.contains('university') ||
        lower.contains('iit') ||
        lower.contains('nit') ||
        lower.contains('institute') ||
        lower.contains('academy')) {
      return 'Educational institute';
    }

    // Health
    if (lower.contains('hospital') ||
        lower.contains('medical') ||
        lower.contains('clinic') ||
        lower.contains('health care') ||
        lower.contains('diagnostic')) {
      return 'Hospital / Health';
    }

    // Shopping
    if (lower.contains('mall') ||
        lower.contains('market') ||
        lower.contains('bazaar') ||
        lower.contains('shopping') ||
        lower.contains('plaza') ||
        lower.contains('complex')) {
      return 'Shopping / Market';
    }

    // Parks / open spaces
    if (lower.contains('park') ||
        lower.contains('garden') ||
        lower.contains('ground') ||
        lower.contains('stadium')) {
      return 'Park / Recreation';
    }

    return 'General area';
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
    for (final c in _companions) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _initAndStartTracking() async {
    // Ask permission & check GPS
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enable GPS to start live tracking'),
        ),
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
          content: Text(
            'Location permission permanently denied. Enable from settings.',
          ),
        ),
      );
      return;
    }

    // Get first fix
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    if (!mounted) return;

    final firstLatLng = LatLng(pos.latitude, pos.longitude);
    final firstSpeedKmh = pos.speed * 3.6;
    final firstMode = _detectModeFromSpeed(firstSpeedKmh);
    final firstTrafficHint = _computeTrafficSignalHint(firstSpeedKmh);

    setState(() {
      _currentPosition = pos;
      _pathPoints.clear();
      _pathPoints.add(firstLatLng);

      // reset trip data
      _origin = firstLatLng;
      _destination = null;
      _totalDistanceKm = 0.0;

      // reset smoothing / hysteresis
      _speedSamples
        ..clear()
        ..add(firstSpeedKmh);
      _pendingMode = firstMode;
      _pendingModeCount = 1;

      _speedKmh = firstSpeedKmh;
      _mode = firstMode;
      _trafficSignalHint = firstTrafficHint;
      _distanceCategory = _computeDistanceCategory(_totalDistanceKm);

      _placeName = 'Detecting place...';
      _placeCategory = 'General area';

      _isTracking = true;

      // Trip summary state
      _tripStartTime = DateTime.now();
      _tripEndTime = null;
      _maxSpeedKmh = firstSpeedKmh;
      _modesUsed
        ..clear()
        ..add(firstMode);
    });

    _moveCameraTo(pos);

    // Start stream with smoothing + hysteresis
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // meters (OS-level filter)
      ),
    ).listen((position) {
      // 0) Instant speed from GPS
      final double instantSpeedKmh = position.speed * 3.6; // m/s → km/h

      // 1) Build smoothed average speed from last N samples
      _speedSamples.add(instantSpeedKmh);
      if (_speedSamples.length > _maxSpeedSamples) {
        _speedSamples.removeAt(0);
      }
      final double avgSpeedKmh = _speedSamples.isEmpty
          ? instantSpeedKmh
          : _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;

      // 2) Use averaged speed for mode + traffic detection
      final String newModeCandidate = _detectModeFromSpeed(avgSpeedKmh);
      final String newTrafficHint = _computeTrafficSignalHint(avgSpeedKmh);

      // 3) Hysteresis: mode must be stable for a few samples before we switch
      if (newModeCandidate == _pendingMode) {
        _pendingModeCount++;
      } else {
        _pendingMode = newModeCandidate;
        _pendingModeCount = 1;
      }

      String effectiveMode = _mode;
      if (_pendingModeCount >= _minSamplesForModeSwitch &&
          newModeCandidate != _mode) {
        effectiveMode = newModeCandidate;
      }

      final LatLng newPoint = LatLng(position.latitude, position.longitude);

      bool shouldUpdatePath = false;
      double segmentMeters = 0;

      // Accuracy filter
      final bool badAccuracy =
      (position.accuracy > _maxAccuracyMeters && position.accuracy != 0.0);

      if (_pathPoints.isEmpty) {
        // First point always used
        shouldUpdatePath = true;
        segmentMeters = 0;
      } else {
        final lastPoint = _pathPoints.last;
        segmentMeters = Geolocator.distanceBetween(
          lastPoint.latitude,
          lastPoint.longitude,
          newPoint.latitude,
          newPoint.longitude,
        );

        final bool smallMovement = segmentMeters < _minMovementMeters;
        final bool lowSpeed = instantSpeedKmh < _minMovementSpeedKmh;

        if (!badAccuracy && !smallMovement && !lowSpeed) {
          shouldUpdatePath = true;
        }
      }

      if (!mounted) return;

      setState(() {
        // Show smoothed speed + stable mode in UI
        _currentPosition = position;
        _speedKmh = avgSpeedKmh;
        _mode = effectiveMode;
        _trafficSignalHint = newTrafficHint;

        if (shouldUpdatePath) {
          _pathPoints.add(newPoint);
          _destination = newPoint;
          _totalDistanceKm += (segmentMeters / 1000.0);
        }

        _distanceCategory = _computeDistanceCategory(_totalDistanceKm);

        // Trip summary stats use smoothed speed
        if (avgSpeedKmh > _maxSpeedKmh) {
          _maxSpeedKmh = avgSpeedKmh;
        }
        if (avgSpeedKmh > 3) {
          _modesUsed.add(effectiveMode);
        }
      });

      // Camera + place lookup only on real movement
      if (shouldUpdatePath) {
        _moveCameraTo(position);
        _maybeUpdatePlace(newPoint);
      }

      // In-trip notifications use stable mode + smoothed speed
      if (avgSpeedKmh > 3 && effectiveMode != _lastNotifiedMode) {
        _lastNotifiedMode = effectiveMode;
        _showInTripSnack(
          title: 'Mode updated',
          message: 'Detected mode: $effectiveMode',
        );
      }

      if (newTrafficHint != _lastNotifiedTrafficHint) {
        _lastNotifiedTrafficHint = newTrafficHint;
        _showInTripSnack(
          title: 'Traffic update',
          message: newTrafficHint,
        );
      }
    });

    // Initial place lookup for origin
    _maybeUpdatePlace(firstLatLng);
  }

  Future<void> _maybeUpdatePlace(LatLng point) async {
    try {
      if (_lastPlaceLookupPoint != null) {
        final dist = Geolocator.distanceBetween(
          _lastPlaceLookupPoint!.latitude,
          _lastPlaceLookupPoint!.longitude,
          point.latitude,
          point.longitude,
        );
        if (dist < _minPlaceLookupDistanceMeters) {
          // too close to last lookup, skip
          return;
        }
      }

      _lastPlaceLookupPoint = point;

      final placemarks = await geocoding.placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );

      if (placemarks.isEmpty) return;

      final p = placemarks.first;

      final parts = <String>{};
      if ((p.name ?? '').trim().isNotEmpty) parts.add(p.name!.trim());
      if ((p.subLocality ?? '').trim().isNotEmpty) {
        parts.add(p.subLocality!.trim());
      }
      if ((p.locality ?? '').trim().isNotEmpty) {
        parts.add(p.locality!.trim());
      }

      final label = parts.isEmpty ? 'Unknown place' : parts.join(', ');

      final combinedText = [
        p.name,
        p.street,
        p.subLocality,
        p.locality,
        p.subAdministrativeArea,
        p.administrativeArea
      ].whereType<String>().join(' ');

      final category = _classifyPlaceCategory(combinedText);

      if (!mounted) return;

      setState(() {
        _placeName = label;
        _placeCategory = category;
      });

      if (label != _lastNotifiedPlaceName) {
        _lastNotifiedPlaceName = label;
        _showInTripSnack(
          title: 'Place detected',
          message: '$label • $category',
        );
      }
    } catch (_) {
      // ignore geocoding errors silently
    }
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
        _tripEndTime = DateTime.now();
      });

      // 🔹 SAVE to Firestore (goes into TripHistory)
      _saveTripToFirestore();

      // Show graphical trip summary
      _showTripSummarySheet();
    } else {
      // Restart
      _initAndStartTracking();
    }
  }

  Future<void> _saveTripToFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final tripsCol = FirebaseFirestore.instance.collection('trips');
      final docRef = tripsCol.doc();

      // Geo path list
      final pathList = _pathPoints
          .map((p) => {
        'lat': p.latitude,
        'lng': p.longitude,
      })
          .toList();

      // automatic duration in minutes
      int? durationMinutes;
      if (_tripStartTime != null && _tripEndTime != null) {
        durationMinutes =
            _tripEndTime!.difference(_tripStartTime!).inMinutes;
      }

      // automatic cost summary (uses you + companions)
      final cost = _computeCostSummary();

      final data = <String, dynamic>{
        'createdBy': uid,

        // Time
        'startTime': _tripStartTime != null
            ? Timestamp.fromDate(_tripStartTime!)
            : null,
        'endTime': _tripEndTime != null
            ? Timestamp.fromDate(_tripEndTime!)
            : null,
        'estimated_duration_minutes': durationMinutes,
        'createdAt': Timestamp.now(),

        // Distances / speeds / modes
        'distance_km': _totalDistanceKm,
        'maxSpeed': _maxSpeedKmh,
        'modesUsed': _modesUsed.toList(),
        'mode': _mode,
        'purpose': 'Live tracked trip',

        // Transport meta
        'transport_type': 'Private',

        // Cost fields (like TripCapture)
        'cost_per_person': cost['costPerPerson'],
        'total_cost': cost['totalCost'],
        'cost_per_person_range': [
          cost['minPerPerson'],
          cost['maxPerPerson'],
        ],
        'total_cost_range': [
          cost['minTotalCost'],
          cost['maxTotalCost'],
        ],

        // Companions (from user input)
        'num_companions': _companions.length,
        'companions_details':
        _companions.map((c) => c.toMap()).toList(),

        // Locations
        'origin_latitude': _origin?.latitude,
        'origin_longitude': _origin?.longitude,
        'destination_latitude': _destination?.latitude,
        'destination_longitude': _destination?.longitude,
        'originPlace': _origin != null
            ? '${_origin!.latitude.toStringAsFixed(5)}, ${_origin!.longitude.toStringAsFixed(5)}'
            : 'Origin (live)',
        'destinationPlace': _placeName,
        'placeCategory': _placeCategory,
        'trafficHint': _trafficSignalHint,
        'distanceCategory': _distanceCategory,

        // Path
        'path': pathList,

        // Tag so history can filter
        'tripType': 'LiveTracking',

        // Trip number
        'trip_number': docRef.id.substring(0, 6).toUpperCase(),
        'status': 'Completed',
      };

      await docRef.set(data);
      // ignore: avoid_print
      print('✔ Live tracking trip saved to Firestore');
    } catch (e) {
      // ignore: avoid_print
      print('❌ Error saving live tracking trip: $e');
    }
  }

  void _showInTripSnack({required String title, required String message}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              message,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'Walking':
        return Icons.directions_walk;
      case 'Cycling':
        return Icons.directions_bike;
      case 'City Vehicle':
        return Icons.directions_car;
      case 'Highway Vehicle':
        return Icons.time_to_leave;
      case 'High Speed':
        return Icons.flight_takeoff;
      case 'Stationary':
        return Icons.self_improvement;
      default:
        return Icons.directions;
    }
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'Walking':
        return const Color(0xFF22C55E);
      case 'Cycling':
        return const Color(0xFF0EA5E9);
      case 'City Vehicle':
        return const Color(0xFF6366F1);
      case 'Highway Vehicle':
        return const Color(0xFFF97316);
      case 'High Speed':
        return const Color(0xFFEC4899);
      case 'Stationary':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF2563EB);
    }
  }

  // 🔹 Companions card UI
  Widget _buildCompanionsCard() {
    final count = _companions.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.group, size: 18, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Companions',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              IconButton(
                onPressed: count > 0
                    ? () {
                  setState(() {
                    final removed = _companions.removeLast();
                    removed.dispose();
                  });
                }
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                color:
                count > 0 ? const Color(0xFFDC2626) : Colors.grey.shade300,
                tooltip: 'Remove companion',
              ),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _companions.add(_CompanionEntry());
                  });
                },
                icon: const Icon(Icons.add_circle_outline),
                color: const Color(0xFF16A34A),
                tooltip: 'Add companion',
              ),
            ],
          ),
          if (count > 0) const SizedBox(height: 6),
          if (count > 0)
            Column(
              children: List.generate(
                count,
                    (index) => _buildCompanionFields(index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompanionFields(int index) {
    final entry = _companions[index];
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Companion ${index + 1}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: entry.emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              isDense: true,
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: entry.ageController,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: false),
                  decoration: const InputDecoration(
                    labelText: 'Age',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: entry.gender,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Male',
                      child: Text('Male'),
                    ),
                    DropdownMenuItem(
                      value: 'Female',
                      child: Text('Female'),
                    ),
                    DropdownMenuItem(
                      value: 'Other',
                      child: Text('Other'),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      entry.gender = v ?? 'Other';
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: entry.relationController,
            decoration: const InputDecoration(
              labelText: 'Relation (e.g., Friend, Family)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          if (index != _companions.length - 1)
            Divider(
              height: 1,
              color: Colors.grey.shade300,
            ),
        ],
      ),
    );
  }

  // 🔹 Bottom sheet: graphical trip summary
  void _showTripSummarySheet() {
    if (!mounted) return;

    final distance = _totalDistanceKm;
    final maxSpeed = _maxSpeedKmh;
    double avgSpeed = 0.0;
    String durationText = 'N/A';

    if (_tripStartTime != null && _tripEndTime != null) {
      final duration = _tripEndTime!.difference(_tripStartTime!);
      final minutes = duration.inMinutes;
      if (minutes > 0) {
        avgSpeed = distance / (minutes / 60.0);
      }

      final h = duration.inHours;
      final m = duration.inMinutes.remainder(60);
      if (h == 0) {
        durationText = '$m min';
      } else {
        durationText = '${h}h ${m}m';
      }
    }

    final modesUsedList = _modesUsed.toList();

    // cost summary for UI
    final cost = _computeCostSummary();
    final int numPersons = cost['numCompanions'];
    final double perPersonCost = cost['costPerPerson'];
    final double totalCost = cost['totalCost'];
    final double minPerPerson = cost['minPerPerson'];
    final double maxPerPerson = cost['maxPerPerson'];
    final double minTotalCost = cost['minTotalCost'];
    final double maxTotalCost = cost['maxTotalCost'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.8;
        return Container(
          height: height,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: 50,
                height: 4,
                margin: const EdgeInsets.only(top: 4, bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Row(
                children: const [
                  Icon(Icons.insights, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Trip Summary',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Distance gauge + core stats
                      Row(
                        children: [
                          SizedBox(
                            width: 130,
                            height: 130,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: SweepGradient(
                                      colors: [
                                        Color(0xFF2563EB),
                                        Color(0xFF22C55E),
                                        Color(0xFFFACC15),
                                        Color(0xFF2563EB),
                                      ],
                                    ),
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF020617),
                                  ),
                                ),
                                SizedBox(
                                  width: 130,
                                  height: 130,
                                  child: CircularProgressIndicator(
                                    value: (distance / 50).clamp(0.0, 1.0),
                                    strokeWidth: 10,
                                    backgroundColor: Colors.white12,
                                    valueColor: const AlwaysStoppedAnimation(
                                      Color(0xFF38BDF8),
                                    ),
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      distance.toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const Text(
                                      'km',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              children: [
                                _SummaryStatTile(
                                  label: 'Duration',
                                  value: durationText,
                                  icon: Icons.schedule,
                                ),
                                const SizedBox(height: 8),
                                _SummaryStatTile(
                                  label: 'Avg speed',
                                  value:
                                  '${avgSpeed.toStringAsFixed(1)} km/h',
                                  icon: Icons.speed,
                                ),
                                const SizedBox(height: 8),
                                _SummaryStatTile(
                                  label: 'Max speed',
                                  value:
                                  '${maxSpeed.toStringAsFixed(1)} km/h',
                                  icon: Icons.local_fire_department,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Modes used
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Modes used',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (modesUsedList.isEmpty)
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Not enough movement to detect modes.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: modesUsedList.map((m) {
                            return Chip(
                              backgroundColor:
                              _modeColor(m).withOpacity(0.18),
                              labelPadding:
                              const EdgeInsets.symmetric(horizontal: 6),
                              avatar: Icon(
                                _modeIcon(m),
                                size: 16,
                                color: _modeColor(m),
                              ),
                              label: Text(
                                m,
                                style: TextStyle(
                                  color: _modeColor(m),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 20),

                      // Bars: distance vs typical, speed vs bands
                      _BarCard(
                        title: 'Distance profile',
                        subtitle: _distanceCategory,
                        valueLabel:
                        '${distance.toStringAsFixed(1)} km • Target: 50 km gauge',
                        value: (distance / 50).clamp(0.0, 1.0),
                      ),
                      const SizedBox(height: 10),
                      _BarCard(
                        title: 'Speed profile',
                        subtitle:
                        'Max vs typical city upper limit (80 km/h)',
                        valueLabel:
                        '${maxSpeed.toStringAsFixed(1)} km/h of 80 km/h',
                        value: (maxSpeed / 80).clamp(0.0, 1.0),
                      ),
                      const SizedBox(height: 10),

                      // Cost estimate card
                      _CostSummaryCard(
                        numCompanions: numPersons,
                        perPerson: perPersonCost,
                        total: totalCost,
                        minPerPerson: minPerPerson,
                        maxPerPerson: maxPerPerson,
                        minTotal: minTotalCost,
                        maxTotal: maxTotalCost,
                      ),
                      const SizedBox(height: 20),

                      // Place cards
                      _PlaceInfoCard(
                        placeName: _placeName,
                        placeCategory: _placeCategory,
                        trafficHint: _trafficSignalHint,
                        distanceCategory: _distanceCategory,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use last filtered path point for marker
    LatLng? currentLatLng;
    if (_pathPoints.isNotEmpty) {
      currentLatLng = _pathPoints.last;
    } else if (_currentPosition != null) {
      currentLatLng = LatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
    } else {
      currentLatLng = null;
    }

    // markers set
    final Set<Marker> markers = {};
    if (currentLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('me'),
          position: currentLatLng,
          infoWindow: const InfoWindow(title: 'You'),
        ),
      );
    }
    if (_origin != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: _origin!,
          infoWindow: const InfoWindow(title: 'Origin'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }
    if (_destination != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _destination!,
          infoWindow: const InfoWindow(title: 'Destination'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
        ),
      );
    }

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
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                              _isTracking
                                  ? 'Tracking in progress'
                                  : 'Tracking stopped',
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.route,
                        size: 18,
                        color: Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Estimated distance: ${_totalDistanceKm.toStringAsFixed(2)} km • $_distanceCategory',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 🔹 Extra row: signal + mode + destination type
                  Row(
                    children: [
                      Expanded(
                        child: _InfoPill(
                          icon: Icons.traffic_rounded,
                          title: 'Signal / Traffic',
                          value: _trafficSignalHint,
                          color: const Color(0xFFFACC15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InfoPill(
                          icon: _modeIcon(_mode),
                          title: 'Mode',
                          value: _mode,
                          color: _modeColor(_mode),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InfoPill(
                          icon: Icons.place,
                          title: 'Destination',
                          value: '$_placeName ($_placeCategory)',
                          color: const Color(0xFF22C55E),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Companions card
          _buildCompanionsCard(),

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
              markers: markers,
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
        backgroundColor:
        _isTracking ? Colors.redAccent : const Color(0xFF2563EB),
        icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
        label: Text(_isTracking ? 'Stop' : 'Start'),
      ),
    );
  }
}

// Small pill widget for top info row
class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _InfoPill({
    Key? key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Summary stat tile (icon + label + value)
class _SummaryStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryStatTile({
    Key? key,
    required this.label,
    required this.value,
    required this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF020617),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Horizontal bar card
class _BarCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String valueLabel;
  final double value;

  const _BarCard({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.valueLabel,
    required this.value,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF020617),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF38BDF8)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valueLabel,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// Cost summary card (similar to TripCapture dialog info)
class _CostSummaryCard extends StatelessWidget {
  final int numCompanions; // here: total persons
  final double perPerson;
  final double total;
  final double minPerPerson;
  final double maxPerPerson;
  final double minTotal;
  final double maxTotal;

  const _CostSummaryCard({
    Key? key,
    required this.numCompanions,
    required this.perPerson,
    required this.total,
    required this.minPerPerson,
    required this.maxPerPerson,
    required this.minTotal,
    required this.maxTotal,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF020617),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cost estimate',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _row(
            label: 'Per person',
            value: '₹${perPerson.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 4),
          _chip(
            'Range: ₹${minPerPerson.toStringAsFixed(0)} - ₹${maxPerPerson.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 10),
          _row(
            label:
            'Total ($numCompanions person${numCompanions > 1 ? "s" : ""})',
            value: '₹${total.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 4),
          _chip(
            'Range: ₹${minTotal.toStringAsFixed(0)} - ₹${maxTotal.toStringAsFixed(0)}',
          ),
        ],
      ),
    );
  }

  static Widget _row({required String label, required String value}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF4ADE80),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
        ),
      ),
    );
  }
}

// Place information card
class _PlaceInfoCard extends StatelessWidget {
  final String placeName;
  final String placeCategory;
  final String trafficHint;
  final String distanceCategory;

  const _PlaceInfoCard({
    Key? key,
    required this.placeName,
    required this.placeCategory,
    required this.trafficHint,
    required this.distanceCategory,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF020617),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Destination context',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 18, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  placeName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.category_outlined,
                  size: 16, color: Colors.white60),
              const SizedBox(width: 6),
              Text(
                placeCategory,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.traffic, size: 16, color: Colors.white60),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  trafficHint,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.directions_car_filled_outlined,
                  size: 16, color: Colors.white60),
              const SizedBox(width: 6),
              Text(
                distanceCategory,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
