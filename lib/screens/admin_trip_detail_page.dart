import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

class AdminTripDetailPage extends StatefulWidget {
  final String tripId;

  const AdminTripDetailPage({
    Key? key,
    required this.tripId,
  }) : super(key: key);

  @override
  State<AdminTripDetailPage> createState() => _AdminTripDetailPageState();
}

class _AdminTripDetailPageState extends State<AdminTripDetailPage> {
  final DateFormat _dateFormat = DateFormat('EEE, dd MMM yyyy HH:mm');

  GoogleMapController? _mapController;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFF7F9FC),
            Color(0xFFEFF6FF),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.8,
          iconTheme: const IconThemeData(color: Color(0xFF111827)),
          title: const Text(
            'Trip Details',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('trips')
              .doc(widget.tripId)
              .get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF2563EB),
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFEF4444), size: 40),
                      const SizedBox(height: 12),
                      const Text(
                        'Unable to load trip',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final data = snapshot.data!.data()!;
            return _buildDetailBody(context, data);
          },
        ),
      ),
    );
  }

  Widget _buildDetailBody(BuildContext context, Map<String, dynamic> data) {
    // ====== BASIC FIELDS ======
    final String tripType =
    (data['tripType'] ?? 'FormCapture').toString(); // LiveTracking / FormCapture
    final bool isLive = tripType == 'LiveTracking';

    final String origin = (data['originPlace'] as String?) ?? 'Origin';
    final String destination =
        (data['destinationPlace'] as String?) ?? 'Destination';

    final String mode = (data['mode'] as String?) ?? 'Mode';
    final String purpose = (data['purpose'] as String?) ?? 'N/A';
    final String transportType =
    ((data['transport_type'] as String?) ?? 'Private').toLowerCase() ==
        'public'
        ? 'Public'
        : 'Private';

    final double distanceKm =
        (data['distance_km'] as num?)?.toDouble() ?? 0.0;
    final double co2Kg = (data['co2_kg'] as num?)?.toDouble() ?? 0.0;
    final double maxSpeed = (data['maxSpeed'] as num?)?.toDouble() ?? 0.0;

    double cost = 0.0;
    if (data.containsKey('total_cost')) {
      cost = (data['total_cost'] as num?)?.toDouble() ?? 0.0;
    } else if (data.containsKey('estimated_cost')) {
      cost = (data['estimated_cost'] as num?)?.toDouble() ?? 0.0;
    } else if (data.containsKey('cost_per_person')) {
      final cpp = (data['cost_per_person'] as num?)?.toDouble() ?? 0.0;
      final companionsCount =
          (data['num_companions'] as num?)?.toInt() ?? 1;
      cost = cpp * companionsCount;
    }

    final Timestamp? startTs = data['startTime'] as Timestamp?;
    final Timestamp? endTs = data['endTime'] as Timestamp?;
    String durationText = 'N/A';
    if (startTs != null && endTs != null) {
      final duration = endTs.toDate().difference(startTs.toDate());
      final h = duration.inHours;
      final m = duration.inMinutes.remainder(60);
      durationText = h == 0 ? '$m min' : '${h}h ${m}m';
    }

    final String status = (data['status'] ?? 'Pending').toString();
    final String createdBy = (data['createdBy'] ?? '').toString();

    final int numCompanions =
        (data['num_companions'] as num?)?.toInt() ?? 0;
    final rawCompanions = data['companions_details'];
    final List<dynamic> companions =
    rawCompanions is List ? rawCompanions : const [];

    // ====== LIVE TRACKING FIELDS ======
    final String placeCategory =
        (data['placeCategory'] as String?) ?? 'General area';
    final String trafficHint =
        (data['trafficHint'] as String?) ?? 'Normal flow';
    final String distanceCategory =
        (data['distanceCategory'] as String?) ?? 'Nearby / Local';

    final List<dynamic> rawModesUsed =
    data['modesUsed'] is List ? data['modesUsed'] as List : const [];
    final List<String> modesUsed =
    rawModesUsed.map((e) => e.toString()).toList();

    // Path for map
    final List<dynamic> rawPath = data['path'] is List ? data['path'] as List : const [];
    final List<LatLng> pathPoints = rawPath.map((p) {
      if (p is Map && p['lat'] != null && p['lng'] != null) {
        return LatLng(
          (p['lat'] as num).toDouble(),
          (p['lng'] as num).toDouble(),
        );
      }
      return const LatLng(0, 0);
    }).where((p) => !(p.latitude == 0 && p.longitude == 0)).toList();

    LatLng? originLatLng;
    LatLng? destLatLng;
    if (data['origin_latitude'] != null && data['origin_longitude'] != null) {
      originLatLng = LatLng(
        (data['origin_latitude'] as num).toDouble(),
        (data['origin_longitude'] as num).toDouble(),
      );
    }
    if (data['destination_latitude'] != null &&
        data['destination_longitude'] != null) {
      destLatLng = LatLng(
        (data['destination_latitude'] as num).toDouble(),
        (data['destination_longitude'] as num).toDouble(),
      );
    }

    // Choose map center
    LatLng? mapCenter;
    if (pathPoints.isNotEmpty) {
      mapCenter = pathPoints.first;
    } else if (originLatLng != null) {
      mapCenter = originLatLng;
    } else if (destLatLng != null) {
      mapCenter = destLatLng;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== MAP SECTION =====
          if (mapCenter != null)
            Container(
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: mapCenter,
                    zoom: 14,
                  ),
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  markers: {
                    if (originLatLng != null)
                      Marker(
                        markerId: const MarkerId('origin'),
                        position: originLatLng,
                        infoWindow: const InfoWindow(title: 'Origin'),
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueGreen,
                        ),
                      ),
                    if (destLatLng != null)
                      Marker(
                        markerId: const MarkerId('destination'),
                        position: destLatLng,
                        infoWindow:
                        const InfoWindow(title: 'Destination'),
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueRed,
                        ),
                      ),
                  },
                  polylines: {
                    if (pathPoints.length > 1)
                      Polyline(
                        polylineId: const PolylineId('path'),
                        points: pathPoints,
                        width: 4,
                        color: const Color(0xFF2563EB),
                      ),
                  },
                ),
              ),
            )
          else
            Container(
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                'No path captured for this trip',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                ),
              ),
            ),

          const SizedBox(height: 16),

          // ===== HEADER CARD =====
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.alt_route,
                        size: 20, color: Color(0xFF2563EB)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$origin → $destination',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _chip(
                      icon: Icons.directions_transit,
                      label: mode,
                    ),
                    _chip(
                      icon: Icons.flag_outlined,
                      label: 'Status: $status',
                    ),
                    _chip(
                      icon: Icons.label_important_outline,
                      label: isLive ? 'Live tracking' : 'Form capture',
                      color: isLive
                          ? const Color(0xFF0EA5E9)
                          : const Color(0xFF6B7280),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ===== TIMING & DISTANCE =====
          _sectionCard(
            title: 'Time & Distance',
            children: [
              _rowTile(
                icon: Icons.play_circle_fill,
                label: 'Start time',
                value: startTs != null
                    ? _dateFormat.format(startTs.toDate())
                    : '—',
              ),
              _rowTile(
                icon: Icons.stop_circle_outlined,
                label: 'End time',
                value: endTs != null
                    ? _dateFormat.format(endTs.toDate())
                    : '—',
              ),
              _rowTile(
                icon: Icons.timelapse,
                label: 'Duration',
                value: durationText,
              ),
              _rowTile(
                icon: Icons.social_distance,
                label: 'Distance',
                value: '${distanceKm.toStringAsFixed(2)} km',
              ),
              if (co2Kg > 0)
                _rowTile(
                  icon: Icons.cloud_outlined,
                  label: 'CO₂ estimate',
                  value: '${co2Kg.toStringAsFixed(2)} kg',
                ),
            ],
          ),

          const SizedBox(height: 14),

          // ===== COST & PURPOSE =====
          _sectionCard(
            title: 'Trip Purpose & Cost',
            children: [
              _rowTile(
                icon: Icons.info_outline,
                label: 'Purpose',
                value: purpose,
              ),
              _rowTile(
                icon: Icons.directions_car_filled_outlined,
                label: 'Transport type',
                value: transportType,
              ),
              if (cost > 0)
                _rowTile(
                  icon: Icons.attach_money,
                  label: 'Cost',
                  value: '₹${cost.toStringAsFixed(0)}',
                ),
            ],
          ),

          const SizedBox(height: 14),

          // ===== LIVE TRACKING SECTION =====
          if (isLive) ...[
            _sectionCard(
              title: 'Live Tracking Summary',
              children: [
                _rowTile(
                  icon: Icons.place_outlined,
                  label: 'Destination category',
                  value: placeCategory,
                ),
                _rowTile(
                  icon: Icons.map_outlined,
                  label: 'Trip distance type',
                  value: distanceCategory,
                ),
                _rowTile(
                  icon: Icons.traffic,
                  label: 'Traffic hint',
                  value: trafficHint,
                ),
                if (maxSpeed > 0)
                  _rowTile(
                    icon: Icons.speed,
                    label: 'Max speed',
                    value: '${maxSpeed.toStringAsFixed(1)} km/h',
                  ),
                if (modesUsed.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Modes detected',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: modesUsed.map((m) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          m,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
          ],

          // ===== COMPANIONS =====
          if (companions.isNotEmpty)
            _sectionCard(
              title: 'Companions',
              children: [
                ...companions.map((c) {
                  final m =
                  c is Map<String, dynamic> ? c : <String, dynamic>{};
                  final name = (m['name'] ?? '—').toString();
                  final age = (m['age'] ?? '—').toString();
                  final gender = (m['gender'] ?? '—').toString();
                  final relation = (m['relation'] ?? '—').toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.person,
                            size: 16, color: Color(0xFF6B7280)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$name ($age, $gender) – $relation',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),

          const SizedBox(height: 14),

          // ===== META =====
          _sectionCard(
            title: 'Metadata',
            children: [
              _rowTile(
                icon: Icons.person_outline,
                label: 'User (createdBy)',
                value: createdBy.isEmpty ? '—' : createdBy,
              ),
              _rowTile(
                icon: Icons.badge_outlined,
                label: 'Trip ID (doc)',
                value: widget.tripId,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==== SMALL UI HELPERS ====

  Widget _chip({
    required IconData icon,
    required String label,
    Color color = const Color(0xFF2563EB),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _rowTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6B7280)),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF111827),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
