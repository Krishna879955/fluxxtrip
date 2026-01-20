import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class TripHistory extends StatelessWidget {
  const TripHistory({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, dd MMM yyyy HH:mm');
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // If somehow user is not logged in
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

            final docs = snapshot.data!.docs;

            // Sort locally instead of Firestore
            docs.sort((a, b) {
              final at = a.data()['startTime'] is Timestamp
                  ? (a.data()['startTime'] as Timestamp).toDate()
                  : DateTime(0);
              final bt = b.data()['startTime'] is Timestamp
                  ? (b.data()['startTime'] as Timestamp).toDate()
                  : DateTime(0);
              return bt.compareTo(at); // latest first
            });

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data();
                final startTime = data['startTime'] is Timestamp
                    ? (data['startTime'] as Timestamp).toDate()
                    : null;
                final endTime = data['endTime'] is Timestamp
                    ? (data['endTime'] as Timestamp).toDate()
                    : null;

                final origin = data['originPlace'] ?? 'Origin';
                final dest = data['destinationPlace'] ?? 'Destination';
                final mode = data['mode'] ?? 'Trip';
                final purpose = data['purpose'] ?? 'N/A';
                final distance =
                    (data['distance_km'] as num?)?.toDouble() ?? 0.0;
                final cost =
                    (data['estimated_cost'] as num?)?.toDouble() ?? 0.0;

                return Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFE0F2FE),
                        child: Icon(
                          _iconForMode(mode),
                          color: const Color(0xFF2563EB),
                          size: 22,
                        ),
                      ),
                      title: Text(
                        '$origin → $dest',
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mode,
                              style: const TextStyle(
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Start: ${startTime != null ? dateFormat.format(startTime) : 'Not set'}',
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'End:   ${endTime != null ? dateFormat.format(endTime) : 'Not set'}',
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Purpose: $purpose',
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                              ),
                            ),
                            if (distance > 0 || cost > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Distance: ${distance.toStringAsFixed(1)} km   |   Est. Cost: ₹${cost.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  static IconData _iconForMode(String mode) {
    final lower = mode.toLowerCase();
    if (lower.contains('car') || lower.contains('taxi') || lower.contains('cab')) {
      return Icons.directions_car_rounded;
    } else if (lower.contains('bus')) {
      return Icons.directions_bus_rounded;
    } else if (lower.contains('train') || lower.contains('metro')) {
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
}
