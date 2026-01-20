import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TripsListPage extends StatelessWidget {
  const TripsListPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    Query<Map<String, dynamic>> baseQuery =
    FirebaseFirestore.instance.collection('trips').orderBy(
      'startTime',
      descending: true,
    );

    // If you want only current user's trips:
    if (uid != null) {
      baseQuery = baseQuery.where('createdBy', isEqualTo: uid);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Trips'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: baseQuery.snapshots(),
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
                child: Text(
                  'Error loading trips:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 14,
                  ),
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No trips found yet.\nStart a trip to see it here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();

              final origin = (data['originPlace'] ?? 'Origin').toString();
              final dest = (data['destinationPlace'] ?? 'Destination').toString();
              final mode = (data['mode'] ?? 'Mode').toString();

              final distanceKm =
                  (data['distance_km'] as num?)?.toDouble() ?? 0.0;
              final cost =
                  (data['estimated_cost'] as num?)?.toDouble() ?? 0.0;

              final startTs = data['startTime'] as Timestamp?;
              final endTs = data['endTime'] as Timestamp?;

              String durationText = '';
              if (startTs != null && endTs != null) {
                final dur =
                    endTs.toDate().difference(startTs.toDate()).inMinutes;
                durationText = '${dur} min';
              }

              final status = (data['status'] ?? 'Pending').toString();

              Color statusBg;
              Color statusText;
              switch (status) {
                case 'Verified':
                  statusBg = const Color(0xFFD1FAE5);
                  statusText = const Color(0xFF047857);
                  break;
                case 'Invalid':
                  statusBg = const Color(0xFFFEE2E2);
                  statusText = const Color(0xFFB91C1C);
                  break;
                case 'Flagged':
                  statusBg = const Color(0xFFFEF3C7);
                  statusText = const Color(0xFF92400E);
                  break;
                default:
                  statusBg = const Color(0xFFE5E7EB);
                  statusText = const Color(0xFF4B5563);
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    // later you can push to a TripDetail page
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: route + status
                        Row(
                          children: [
                            const Icon(
                              Icons.route,
                              size: 18,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$origin → $dest',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: statusBg,
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: statusText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mode: $mode • ${distanceKm.toStringAsFixed(1)} km • ₹${cost.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (startTs != null)
                          Text(
                            'Start: ${startTs.toDate()}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        if (endTs != null)
                          Text(
                            'End:   ${endTs.toDate()}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        if (durationText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Duration: $durationText',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
