import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class EndToEndNavigationPage extends StatefulWidget {
  const EndToEndNavigationPage({Key? key}) : super(key: key);

  @override
  State<EndToEndNavigationPage> createState() => _EndToEndNavigationPage();
}

class _EndToEndNavigationPage extends State<EndToEndNavigationPage> {
  bool _isTracking = false;
  Position? _lastPosition;
  Position? _firstPosition;
  DateTime? _startTime;
  DateTime? _endTime;
  double _distanceMeters = 0;
  double _currentSpeedKmh = 0;

  StreamSubscription<Position>? _positionSub;

  // Counts of detected modes during tracking
  final Map<String, int> _modeCounts = {
    'Walk': 0,
    'Bicycle': 0,
    'Car': 0,
    'Bus': 0,
    'Train': 0,
  };

  // Same style as your TripCapture cost map
  final Map<String, double> _costPerKm = const {
    'Car': 15.0,
    'Taxi': 20.0,
    'Motorcycle': 10.0,
    'Bus': 5.0,
    'Train': 3.0,
    'Metro': 4.0,
    'Other': 8.0,
    'Walk': 0.0,
    'Bicycle': 0.0,
  };

  String _currentMode = 'Detecting...';

  // NEW: keep recent speeds for smoothing
  final List<double> _recentSpeedsKmh = [];
  static const int _speedWindowSize = 8;

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _startTracking() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Location services are disabled. Please enable GPS.',
            isError: true);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnack('Location permission denied.', isError: true);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnack(
          'Location permission permanently denied. Enable it from Settings.',
          isError: true,
        );
        return;
      }

      setState(() {
        _isTracking = true;
        _distanceMeters = 0;
        _currentSpeedKmh = 0;
        _recentSpeedsKmh.clear(); // reset smoothing window
        _modeCounts.updateAll((key, value) => 0);
        _currentMode = 'Detecting...';
        _startTime = DateTime.now();
        _endTime = null;
        _lastPosition = null;
        _firstPosition = null;
      });

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 10, // meters between updates
        ),
      ).listen((Position position) {
        setState(() {
          if (_firstPosition == null) {
            _firstPosition = position;
          }

          if (_lastPosition != null &&
              _lastPosition!.timestamp != null &&
              position.timestamp != null) {
            final dtSeconds = position.timestamp!
                .difference(_lastPosition!.timestamp!)
                .inMilliseconds /
                1000.0;

            final segmentDistance = Geolocator.distanceBetween(
              _lastPosition!.latitude,
              _lastPosition!.longitude,
              position.latitude,
              position.longitude,
            );

            _distanceMeters += segmentDistance;

            if (dtSeconds > 0) {
              // instantaneous segment speed
              final segmentSpeedKmh = (segmentDistance / dtSeconds) * 3.6;

              // ignore clearly bogus spikes
              if (segmentSpeedKmh > 0 && segmentSpeedKmh < 200) {
                // add to sliding window
                _recentSpeedsKmh.add(segmentSpeedKmh);
                if (_recentSpeedsKmh.length > _speedWindowSize) {
                  _recentSpeedsKmh.removeAt(0);
                }

                // smoothed speed = average of window
                final avgSpeed = _recentSpeedsKmh.reduce((a, b) => a + b) /
                    _recentSpeedsKmh.length;
                _currentSpeedKmh = avgSpeed;

                final detectedMode = _inferModeFromSpeed(avgSpeed);
                _modeCounts[detectedMode] =
                    (_modeCounts[detectedMode] ?? 0) + 1;
                _currentMode = detectedMode;
              }
            }
          }

          _lastPosition = position;
        });
      });
    } catch (e) {
      _showSnack('Failed to start tracking: $e', isError: true);
    }
  }

  Future<void> _stopTracking() async {
    if (!_isTracking) return;

    await _positionSub?.cancel();
    _positionSub = null;

    setState(() {
      _isTracking = false;
      _endTime = DateTime.now();
    });

    if (_startTime == null || _lastPosition == null || _firstPosition == null) {
      _showSnack('Not enough data collected. Try tracking for a bit longer.',
          isError: true);
      return;
    }

    final distanceKm = _distanceMeters / 1000.0;
    final autoMode = _getDominantMode();
    final estimatedCost =
        distanceKm * (_costPerKm[autoMode] ?? _costPerKm['Other']!);

    _showSaveDialog(
      distanceKm: distanceKm,
      autoMode: autoMode,
      estimatedCost: estimatedCost,
    );
  }

  // UPDATED: smarter thresholds
  String _inferModeFromSpeed(double speedKmh) {
    // small jitter / standing / walking slowly
    if (speedKmh < 2) return 'Walk';

    // human-powered
    if (speedKmh < 10) return 'Walk';
    if (speedKmh < 22) return 'Bicycle';

    // motorised
    if (speedKmh < 50) return 'Car'; // typical city car
    if (speedKmh < 90) return 'Bus'; // bus / highway

    return 'Train'; // very fast = train / long highway
  }

  String _getDominantMode() {
    String best = 'Car';
    int bestCount = -1;

    _modeCounts.forEach((mode, count) {
      if (count > bestCount) {
        bestCount = count;
        best = mode;
      }
    });

    return best;
  }

  Future<void> _showSaveDialog({
    required double distanceKm,
    required String autoMode,
    required double estimatedCost,
  }) async {
    final TextEditingController purposeCtrl = TextEditingController();
    String selectedMode = autoMode;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Wrap(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const Text(
                    'Live Trip Summary',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _summaryChip(
                        icon: Icons.route_rounded,
                        label: 'Distance',
                        value: '${distanceKm.toStringAsFixed(2)} km',
                      ),
                      const SizedBox(width: 8),
                      _summaryChip(
                        icon: Icons.speed_rounded,
                        label: 'Mode',
                        value: autoMode,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_startTime != null)
                        Expanded(
                          child: Text(
                            'Start: ${dateFormat.format(_startTime!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      if (_endTime != null)
                        Expanded(
                          child: Text(
                            'End: ${dateFormat.format(_endTime!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Estimated cost: ₹${estimatedCost.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Detected mode (you can change it):',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedMode,
                    decoration: const InputDecoration(
                      labelText: 'Mode of travel',
                    ),
                    items: const [
                      'Walk',
                      'Bicycle',
                      'Car',
                      'Taxi',
                      'Motorcycle',
                      'Bus',
                      'Train',
                      'Metro',
                      'Other',
                    ].map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(m),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      selectedMode = v;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: purposeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Purpose of trip (optional)',
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Discard'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            await _saveTrip(
                              distanceKm: distanceKm,
                              mode: selectedMode,
                              cost: estimatedCost,
                              purpose: purposeCtrl.text.trim(),
                            );
                            if (!mounted) return;
                            Navigator.of(ctx).pop(); // close bottom sheet
                            Navigator.of(context).pop(); // back to dashboard
                          },
                          child: const Text('Save Trip'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveTrip({
    required double distanceKm,
    required String mode,
    required double cost,
    required String purpose,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnack('Not logged in. Cannot save trip.', isError: true);
        return;
      }

      final Map<String, dynamic> data = {
        'originPlace': 'Live tracking start',
        'destinationPlace': 'Live tracking end',
        'startTime': _startTime != null ? Timestamp.fromDate(_startTime!) : null,
        'endTime': _endTime != null ? Timestamp.fromDate(_endTime!) : null,
        'mode': mode,
        'purpose': purpose.isEmpty ? 'N/A' : purpose,
        'distance_km': distanceKm,
        'estimated_cost': cost,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'autoDetected': true,
      };

      if (_firstPosition != null && _lastPosition != null) {
        data.addAll({
          'origin_latitude': _firstPosition!.latitude,
          'origin_longitude': _firstPosition!.longitude,
          'destination_latitude': _lastPosition!.latitude,
          'destination_longitude': _lastPosition!.longitude,
        });
      }

      await FirebaseFirestore.instance.collection('trips').add(data);
      _showSnack('Live trip saved successfully!');
    } catch (e) {
      _showSnack('Failed to save trip: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  Widget _summaryChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF2563EB)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = _distanceMeters / 1000.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking (Auto Mode)'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Status card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x11000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _isTracking
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF9CA3AF),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isTracking ? 'Tracking in progress' : 'Not tracking',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _infoTile(
                          label: 'Distance',
                          value: '${distanceKm.toStringAsFixed(2)} km',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _infoTile(
                          label: 'Speed',
                          value: '${_currentSpeedKmh.toStringAsFixed(1)} km/h',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _infoTile(
                    label: 'Detected mode',
                    value: _currentMode,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isTracking ? null : _startTracking,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start Tracking'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTracking ? _stopTracking : null,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop & Save'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      foregroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Keep this screen open while tracking for best accuracy.',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
