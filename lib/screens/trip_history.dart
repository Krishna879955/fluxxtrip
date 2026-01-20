import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class TripHistory extends StatefulWidget {
  const TripHistory({Key? key}) : super(key: key);

  @override
  State<TripHistory> createState() => _TripHistoryState();
}

class _TripHistoryState extends State<TripHistory> {
  final dateFormat = DateFormat('EEE, dd MMM yyyy HH:mm');

  // 'All', 'Captured', 'Live'
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Not logged in
    if (uid == null) {
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
              'Trip History',
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'You must be logged in to view your trip history.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      );
    }

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
            'Trip History',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('trips')
              .where('createdBy', isEqualTo: uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF2563EB),
                ),
              );
            }

            if (snapshot.hasError) {
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
                        'Something went wrong',
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

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.map_outlined,
                          size: 50, color: Color(0xFF9CA3AF)),
                      SizedBox(height: 12),
                      Text(
                        'No trips found',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Once you start capturing trips, they will show up here with full details.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final allDocs = snapshot.data!.docs;

            // Sort locally - latest startTime first
            allDocs.sort((a, b) {
              final at = a.data()['startTime'] is Timestamp
                  ? (a.data()['startTime'] as Timestamp).toDate()
                  : DateTime.fromMillisecondsSinceEpoch(0);
              final bt = b.data()['startTime'] is Timestamp
                  ? (b.data()['startTime'] as Timestamp).toDate()
                  : DateTime.fromMillisecondsSinceEpoch(0);
              return bt.compareTo(at);
            });

            // Filter by tripType
            final filteredDocs = allDocs.where((doc) {
              final data = doc.data();
              final tripType =
                  (data['tripType'] as String?) ?? 'Captured'; // default
              if (_filter == 'Captured') {
                return tripType != 'LiveTracking';
              } else if (_filter == 'Live') {
                return tripType == 'LiveTracking';
              }
              return true; // All
            }).toList();

            if (filteredDocs.isEmpty) {
              return Column(
                children: [
                  _buildFilterRow(),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.download,
                            size: 18, color: Color(0xFF9CA3AF)),
                        label: const Text(
                          'Export CSV',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'No trips match this filter.',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                _buildFilterRow(),
                // Export CSV button (uses current filtered trips)
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF2563EB),
                      ),
                      onPressed: () => _exportTripsToCsv(filteredDocs),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text(
                        'Export CSV',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data();

                      // Times
                      final startTime = data['startTime'] is Timestamp
                          ? (data['startTime'] as Timestamp).toDate()
                          : null;
                      final endTime = data['endTime'] is Timestamp
                          ? (data['endTime'] as Timestamp).toDate()
                          : null;

                      final origin =
                          (data['originPlace'] as String?) ?? 'Origin';
                      final dest =
                          (data['destinationPlace'] as String?) ?? 'Destination';
                      final mode = (data['mode'] as String?) ?? 'Trip';
                      final purpose = (data['purpose'] as String?) ?? 'N/A';
                      final distance =
                          (data['distance_km'] as num?)?.toDouble() ?? 0.0;

                      // Transport type chip
                      final String rawTransportType =
                          (data['transport_type'] as String?) ?? 'Private';
                      final String transportType =
                      rawTransportType.toLowerCase() == 'public'
                          ? 'Public'
                          : 'Private';

                      // Cost
                      double cost = 0.0;
                      if (data.containsKey('total_cost')) {
                        cost =
                            (data['total_cost'] as num?)?.toDouble() ?? 0.0;
                      } else if (data.containsKey('estimated_cost')) {
                        cost =
                            (data['estimated_cost'] as num?)?.toDouble() ?? 0.0;
                      } else if (data.containsKey('cost_per_person')) {
                        final cpp =
                            (data['cost_per_person'] as num?)?.toDouble() ??
                                0.0;
                        final companionsCount =
                            (data['num_companions'] as num?)?.toInt() ?? 1;
                        cost = cpp * companionsCount;
                      }

                      // Companions
                      final numCompanions =
                          (data['num_companions'] as num?)?.toInt() ?? 0;
                      final rawCompanions = data['companions_details'];
                      final List<dynamic> companions =
                      rawCompanions is List ? rawCompanions : const [];

                      // Companion emails (email first, fallback to name)
                      final List<String> companionEmails = companions
                          .whereType<Map<String, dynamic>>()
                          .map((m) {
                        final email =
                        (m['email'] ?? '').toString().trim();
                        final name =
                        (m['name'] ?? '').toString().trim();
                        return email.isNotEmpty ? email : name;
                      })
                          .where((v) => v.isNotEmpty)
                          .toList();

                      // Label for companions pill
                      String? companionsLabel;
                      if (numCompanions > 0) {
                        if (companionEmails.isNotEmpty) {
                          final preview = companionEmails.take(2).join(', ');
                          final extra =
                          companionEmails.length > 2 ? ' +' : '';
                          companionsLabel =
                          'Companions: $numCompanions • $preview$extra';
                        } else {
                          companionsLabel = 'Companions: $numCompanions';
                        }
                      }

                      // Live tracking extras
                      final tripType =
                          (data['tripType'] as String?) ?? 'Captured';
                      final placeCategory =
                          (data['placeCategory'] as String?) ?? '';
                      final trafficHint =
                          (data['trafficHint'] as String?) ?? '';
                      final distanceCategory =
                          (data['distanceCategory'] as String?) ?? '';
                      final maxSpeed =
                      (data['maxSpeed'] as num?)?.toDouble();

                      // Trip number
                      final rawTripNumber =
                          data['trip_number'] ?? data['tripNumber'];
                      final fallbackId = doc.id;
                      final tripNumber =
                          rawTripNumber ?? fallbackId.substring(0, 6).toUpperCase();

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Container(
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
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              // Optional: detail page
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // LEFT
                                  Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius:
                                          BorderRadius.circular(12),
                                          border: Border.all(
                                            color: const Color(0xFFBEE3F8),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                                Icons.confirmation_num,
                                                size: 14,
                                                color: Color(0xFF2563EB)),
                                            const SizedBox(width: 6),
                                            Text(
                                              '#$tripNumber',
                                              style: const TextStyle(
                                                color: Color(0xFF2563EB),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor:
                                        const Color(0xFFE0F2FE),
                                        child: Icon(
                                          _iconForMode(mode),
                                          color: const Color(0xFF2563EB),
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: tripType == 'LiveTracking'
                                              ? const Color(0xFFE0F2FE)
                                              : const Color(0xFFFEF9C3),
                                          borderRadius:
                                          BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          tripType == 'LiveTracking'
                                              ? 'Live'
                                              : 'Captured',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: tripType == 'LiveTracking'
                                                ? const Color(0xFF1D4ED8)
                                                : const Color(0xFF92400E),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(width: 12),

                                  // RIGHT
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$origin → $dest',
                                          style: const TextStyle(
                                            color: Color(0xFF111827),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            _infoPill(
                                              Icons.calendar_today,
                                              startTime != null
                                                  ? dateFormat.format(startTime)
                                                  : 'Start: —',
                                            ),
                                            _infoPill(
                                              Icons.schedule,
                                              endTime != null
                                                  ? dateFormat.format(endTime)
                                                  : 'End: —',
                                            ),

                                            // Mode of Transport with correct icon
                                            _infoPill(
                                              _iconForMode(mode),
                                              mode,
                                            ),

                                            // Public / Private Transport type


                                            _infoPill(
                                              Icons.info_outline,
                                              'Purpose: $purpose',
                                            ),
                                            if (distance > 0)
                                              _infoPill(
                                                Icons.alt_route,
                                                '${distance.toStringAsFixed(1)} km',
                                              ),
                                            if (cost > 0)
                                              _infoPill(
                                                Icons.attach_money,
                                                '₹${cost.toStringAsFixed(0)}',
                                              ),
                                            if (companionsLabel != null)
                                              _infoPill(
                                                Icons.group,
                                                companionsLabel!,
                                              ),
                                            if (tripType == 'LiveTracking' &&
                                                maxSpeed != null)
                                              _infoPill(
                                                Icons.speed,
                                                'Max ${maxSpeed.toStringAsFixed(1)} km/h',
                                              ),
                                            if (tripType == 'LiveTracking' &&
                                                distanceCategory.isNotEmpty)
                                              _infoPill(
                                                Icons.stacked_line_chart,
                                                distanceCategory,
                                              ),
                                            if (tripType == 'LiveTracking' &&
                                                placeCategory.isNotEmpty)
                                              _infoPill(
                                                Icons.category_outlined,
                                                placeCategory,
                                              ),
                                          ],
                                        ),

                                        const SizedBox(height: 8),
                                        Container(
                                          height: 1,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius:
                                            BorderRadius.circular(2),
                                          ),
                                        ),
                                        const SizedBox(height: 6),

                                        if (companions.isNotEmpty) ...[
                                          ExpansionTile(
                                            tilePadding: EdgeInsets.zero,
                                            collapsedIconColor:
                                            const Color(0xFF2563EB),
                                            iconColor:
                                            const Color(0xFF2563EB),
                                            childrenPadding:
                                            const EdgeInsets.only(top: 4),
                                            title: const Text(
                                              'View companions details',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Color(0xFF2563EB),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            children: companions.map((c) {
                                              final m = c
                                              is Map<String, dynamic>
                                                  ? c
                                                  : <String, dynamic>{};
                                              final email =
                                              (m['email'] ?? '')
                                                  .toString();
                                              final name =
                                              (m['name'] ?? '—')
                                                  .toString();
                                              final age =
                                              (m['age'] ?? '—')
                                                  .toString();
                                              final gender =
                                              (m['gender'] ?? '—')
                                                  .toString();
                                              final relation =
                                              (m['relation'] ?? '—')
                                                  .toString();

                                              final primary =
                                              email.isNotEmpty
                                                  ? email
                                                  : name;

                                              return Padding(
                                                padding:
                                                const EdgeInsets.only(
                                                    bottom: 4.0),
                                                child: Row(
                                                  crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                                  children: [
                                                    const Icon(Icons.person,
                                                        size: 16,
                                                        color: Color(
                                                            0xFF6B7280)),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        '$primary ($age, $gender) – $relation',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Color(
                                                              0xFF4B5563),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                          const SizedBox(height: 4),
                                        ],

                                        if (tripType == 'LiveTracking' &&
                                            trafficHint.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 4.0),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.traffic,
                                                    size: 16,
                                                    color: Color(0xFFFB923C)),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    trafficHint,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                      Color(0xFF92400E),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                'Captured by you',
                                                style: TextStyle(
                                                  color: Colors
                                                      .grey.shade600,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                TextOverflow.ellipsis,
                                                softWrap: false,
                                              ),
                                            ),
                                            if (startTime != null) ...[
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  dateFormat.format(startTime),
                                                  style: TextStyle(
                                                    color: Colors
                                                        .grey.shade600,
                                                    fontSize: 12,
                                                  ),
                                                  textAlign:
                                                  TextAlign.right,
                                                  maxLines: 1,
                                                  overflow: TextOverflow
                                                      .ellipsis,
                                                  softWrap: false,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),

                                        const SizedBox(height: 6),

                                        Row(
                                          mainAxisAlignment:
                                          MainAxisAlignment.end,
                                          children: [
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _showUpdateTripDialog(doc),
                                              icon: const Icon(Icons.edit,
                                                  size: 16),
                                              label: const Text(
                                                'Edit',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _confirmDeleteTrip(doc),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 16,
                                                color: Colors.redAccent,
                                              ),
                                              label: const Text(
                                                'Delete',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.redAccent,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // EXPORT CSV
  Future<void> _exportTripsToCsv(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    if (docs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No trips to export for this filter.'),
        ),
      );
      return;
    }

    try {
      final buffer = StringBuffer();

      buffer.writeln([
        'Trip ID',
        'Trip Number',
        'Trip Type',
        'Created By',
        'Start Time',
        'End Time',
        'Origin',
        'Destination',
        'Mode',
        'Transport Type',
        'Purpose',
        'Distance (km)',
        'Total Cost',
        'Cost Per Person',
        'Num Companions',
        'Companions Details',
        'Place Category',
        'Distance Category',
        'Traffic Hint',
        'Max Speed (km/h)',
        'Estimated Duration (min)',
      ].map(_csvEscape).join(','));

      for (final doc in docs) {
        final data = doc.data();

        final String id = doc.id;
        final rawTripNumber = data['trip_number'] ?? data['tripNumber'];
        final String tripNumber = (rawTripNumber ?? '').toString();

        final String tripType =
            (data['tripType'] as String?) ?? 'Captured';
        final String createdBy =
        (data['createdBy'] ?? '').toString();

        DateTime? startTime;
        DateTime? endTime;
        if (data['startTime'] is Timestamp) {
          startTime = (data['startTime'] as Timestamp).toDate();
        }
        if (data['endTime'] is Timestamp) {
          endTime = (data['endTime'] as Timestamp).toDate();
        }

        final String startTimeStr =
        startTime != null ? dateFormat.format(startTime) : '';
        final String endTimeStr =
        endTime != null ? dateFormat.format(endTime) : '';

        final String origin =
            (data['originPlace'] as String?) ?? '';
        final String dest =
            (data['destinationPlace'] as String?) ?? '';
        final String mode =
            (data['mode'] as String?) ?? '';
        final String purpose =
            (data['purpose'] as String?) ?? '';

        final double distance =
            (data['distance_km'] as num?)?.toDouble() ?? 0.0;

        final String rawTransportType =
            (data['transport_type'] as String?) ?? 'Private';
        final String transportType =
        rawTransportType.toLowerCase() == 'public'
            ? 'Public'
            : 'Private';

        double totalCost = 0.0;
        double costPerPerson =
            (data['cost_per_person'] as num?)?.toDouble() ?? 0.0;

        if (data.containsKey('total_cost')) {
          totalCost =
              (data['total_cost'] as num?)?.toDouble() ?? 0.0;
        } else if (data.containsKey('estimated_cost')) {
          totalCost =
              (data['estimated_cost'] as num?)?.toDouble() ?? 0.0;
        } else if (costPerPerson > 0) {
          final companionsCount =
              (data['num_companions'] as num?)?.toInt() ?? 1;
          totalCost = costPerPerson * companionsCount;
        }

        final int numCompanions =
            (data['num_companions'] as num?)?.toInt() ?? 0;

        final rawCompanions = data['companions_details'];
        final List<dynamic> companions =
        rawCompanions is List ? rawCompanions : const [];

        // Include email in CSV summary (email preferred, fallback to name)
        final String companionsSummary = companions
            .map((c) {
          final m =
          c is Map<String, dynamic> ? c : <String, dynamic>{};
          final email = (m['email'] ?? '').toString();
          final name = (m['name'] ?? '').toString();
          final age = (m['age'] ?? '').toString();
          final gender = (m['gender'] ?? '').toString();
          final relation = (m['relation'] ?? '').toString();

          final primary = email.isNotEmpty ? email : name;

          if (primary.isEmpty &&
              age.isEmpty &&
              gender.isEmpty &&
              relation.isEmpty) {
            return '';
          }
          return '$primary ($age, $gender) - $relation';
        })
            .where((e) => e.isNotEmpty)
            .join(' | ');

        final String placeCategory =
            (data['placeCategory'] as String?) ?? '';
        final String distanceCategory =
            (data['distanceCategory'] as String?) ?? '';
        final String trafficHint =
            (data['trafficHint'] as String?) ?? '';
        final double maxSpeed =
            (data['maxSpeed'] as num?)?.toDouble() ?? 0.0;
        final int estimatedMinutes =
            (data['estimated_duration_minutes'] as num?)
                ?.toInt() ??
                0;

        buffer.writeln([
          id,
          tripNumber,
          tripType,
          createdBy,
          startTimeStr,
          endTimeStr,
          origin,
          dest,
          mode,
          transportType,
          purpose,
          distance.toStringAsFixed(2),
          totalCost.toStringAsFixed(2),
          costPerPerson.toStringAsFixed(2),
          numCompanions.toString(),
          companionsSummary,
          placeCategory,
          distanceCategory,
          trafficHint,
          maxSpeed > 0 ? maxSpeed.toStringAsFixed(1) : '',
          estimatedMinutes > 0 ? estimatedMinutes.toString() : '',
        ].map(_csvEscape).join(','));
      }

      final directory = await getTemporaryDirectory();
      final filePath =
          '${directory.path}/trip_history_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File(filePath);
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Trip history CSV export',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
          Text('CSV generated. Choose where to save/share it.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export CSV: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  String _csvEscape(String? input) {
    if (input == null) return '';
    String value = input;
    if (value.contains('"')) {
      value = value.replaceAll('"', '""');
    }
    if (value.contains(',') ||
        value.contains('\n') ||
        value.contains('\r')) {
      value = '"$value"';
    }
    return value;
  }

  Widget _buildFilterRow() {
    return Padding(
      padding:
      const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 4),
      child: Row(
        children: [
          _buildFilterChip('All', Icons.all_inclusive),
          const SizedBox(width: 8),
          _buildFilterChip('Captured', Icons.edit_location_alt),
          const SizedBox(width: 8),
          _buildFilterChip('Live', Icons.wifi_tethering),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, IconData icon) {
    final bool selected = _filter == label;
    return ChoiceChip(
      selected: selected,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : const Color(0xFF2563EB),
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : const Color(0xFF1E293B),
        ),
      ),
      selectedColor: const Color(0xFF2563EB),
      backgroundColor: const Color(0xFFE5EDFF),
      onSelected: (_) {
        setState(() {
          _filter = label;
        });
      },
    );
  }

  Widget _infoPill(IconData icon, String text) {
    // leave space for left column + padding; adjust if needed
    final double maxWidth = MediaQuery.of(context).size.width - 140;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE6EEF8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF2563EB)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2, // wrap into 2 lines max
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForMode(String mode) {
    final lower = mode.toLowerCase();
    if (lower.contains('car') ||
        lower.contains('taxi') ||
        lower.contains('cab')) {
      return Icons.directions_car_rounded;
    } else if (lower.contains('bus')) {
      return Icons.directions_bus_rounded;
    } else if (lower.contains('train') ||
        lower.contains('metro')) {
      return Icons.train_rounded;
    } else if (lower.contains('bike') ||
        lower.contains('bicycle') ||
        lower.contains('cycle') ||
        lower.contains('motorcycle')) {
      return Icons.pedal_bike_rounded;
    } else if (lower.contains('walk') || lower.contains('foot')) {
      return Icons.directions_walk_rounded;
    }
    return Icons.directions_transit_filled_rounded;
  }

  Future<void> _confirmDeleteTrip(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final origin =
        (data['originPlace'] as String?) ?? 'Origin';
    final dest =
        (data['destinationPlace'] as String?) ?? 'Destination';

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete trip'),
        content: Text(
          'Are you sure you want to delete this trip:\n$origin → $dest ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await doc.reference.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete trip: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _showUpdateTripDialog(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();

    final originController = TextEditingController(
        text: data['originPlace'] as String? ?? '');
    final destController = TextEditingController(
        text: data['destinationPlace'] as String? ?? '');
    final purposeController = TextEditingController(
        text: data['purpose'] as String? ?? '');
    final modeController =
    TextEditingController(text: data['mode'] as String? ?? '');
    final transportTypeController = TextEditingController(
        text: data['transport_type'] as String? ?? '');
    final distanceController = TextEditingController(
        text: (data['distance_km'] as num?)?.toString() ?? '');
    final companionsController = TextEditingController(
        text: (data['num_companions'] as num?)?.toInt().toString() ?? '');
    final costController = TextEditingController(
      text: (data['total_cost'] ??
          data['estimated_cost'] ??
          data['cost_per_person'] ??
          '')
          .toString(),
    );

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Edit trip details',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Origin & Destination
              TextField(
                controller: originController,
                decoration: const InputDecoration(
                  labelText: 'Origin',
                  hintText: 'Eg. Bharuch Railway Station',
                  prefixIcon: Icon(Icons.trip_origin),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: destController,
                decoration: const InputDecoration(
                  labelText: 'Destination',
                  hintText: 'Eg. Vadodara Bus Stand',
                  prefixIcon: Icon(Icons.flag),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Purpose
              TextField(
                controller: purposeController,
                decoration: const InputDecoration(
                  labelText: 'Purpose',
                  hintText: 'Eg. College, Office, Vacation',
                  prefixIcon: Icon(Icons.info_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Mode + Transport type
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: modeController,
                      decoration: const InputDecoration(
                        labelText: 'Mode',
                        hintText: 'Car, Bus, Train, Walk…',
                        prefixIcon: Icon(Icons.directions_transit),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: transportTypeController,
                      decoration: const InputDecoration(
                        labelText: 'Transport type',
                        hintText: 'Public / Private',
                        prefixIcon: Icon(Icons.swap_horiz),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Distance + Companions
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: distanceController,
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Distance (km)',
                        hintText: 'Eg. 12.5',
                        prefixIcon: Icon(Icons.alt_route),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: companionsController,
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                      decoration: const InputDecoration(
                        labelText: 'Companions',
                        hintText: 'Eg. 2',
                        prefixIcon: Icon(Icons.group),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Cost
              TextField(
                controller: costController,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Total cost (₹)',
                  hintText: 'Eg. 250',
                  prefixIcon: Icon(Icons.currency_rupee),
                  helperText: 'Approx total cost for this trip',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actionsPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.save, size: 18),
            label: const Text(
              'Save changes',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (saved != true) return;

    try {
      final double? parsedCost =
      double.tryParse(costController.text.trim());
      final double? parsedDistance =
      double.tryParse(distanceController.text.trim());
      final int? parsedCompanions =
      int.tryParse(companionsController.text.trim());

      await doc.reference.update({
        'originPlace': originController.text.trim(),
        'destinationPlace': destController.text.trim(),
        'purpose': purposeController.text.trim(),
        'mode': modeController.text.trim(),
        'transport_type': transportTypeController.text.trim(),
        if (parsedDistance != null) 'distance_km': parsedDistance,
        if (parsedCompanions != null) 'num_companions': parsedCompanions,
        if (parsedCost != null) 'total_cost': parsedCost,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update trip: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}
