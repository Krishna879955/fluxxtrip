import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TripsListPage extends StatefulWidget {
  const TripsListPage({Key? key}) : super(key: key);

  @override
  State<TripsListPage> createState() => _TripsListPageState();
}

class _TripsListPageState extends State<TripsListPage> {
  String _selectedModeFilter = 'All';

  final List<String> _modes = [
    'All',
    'Bus',
    'Train',
    'Car',
    'Motorcycle',
    'Bicycle',
    'Walk',
    'Taxi',
    'Metro',
    'Other',
  ];

  IconData _iconForMode(String mode) {
    final m = mode.toLowerCase();
    if (m.contains('car') || m.contains('taxi') || m.contains('cab')) {
      return Icons.directions_car_rounded;
    } else if (m.contains('bus')) {
      return Icons.directions_bus_rounded;
    } else if (m.contains('train') || m.contains('metro')) {
      return Icons.train_rounded;
    } else if (m.contains('cycle') || m.contains('bike')) {
      return Icons.pedal_bike_rounded;
    } else if (m.contains('walk')) {
      return Icons.directions_walk_rounded;
    }
    return Icons.place_rounded;
  }

  @override
  Widget build(BuildContext context) {
    Query tripsQuery = FirebaseFirestore.instance
        .collection('trips')
        .orderBy('createdAt', descending: true);

    if (_selectedModeFilter != 'All') {
      tripsQuery = tripsQuery.where('mode', isEqualTo: _selectedModeFilter);
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
          elevation: 1,
          backgroundColor: Colors.white,
          title: const Text(
            'All Trips',
            style: TextStyle(
              color: Color(0xFF1E293B),
              fontWeight: FontWeight.w600,
            ),
          ),
          iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        ),
        body: Column(
          children: [
            // FILTER DROPDOWN
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: DropdownButtonFormField<String>(
                value: _selectedModeFilter,
                decoration: InputDecoration(
                  labelText: 'Filter by mode',
                  labelStyle: const TextStyle(color: Color(0xFF64748B)),
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon:
                  const Icon(Icons.filter_alt_rounded, color: Color(0xFF2563EB)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                iconEnabledColor: const Color(0xFF2563EB),
                style: const TextStyle(color: Color(0xFF111827)),
                items: _modes.map((m) {
                  return DropdownMenuItem<String>(
                    value: m,
                    child: Text(m),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedModeFilter = value ?? 'All';
                  });
                },
              ),
            ),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: tripsQuery.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Error loading trips!',
                        style: TextStyle(color: Color(0xFFEF4444)),
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2563EB),
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'No trips found.',
                        style: TextStyle(color: Color(0xFF6B7280)),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;

                      final origin = data['originPlace'] ?? 'Unknown origin';
                      final dest = data['destinationPlace'] ?? 'Unknown destination';
                      final mode = data['mode'] ?? 'Unknown';
                      final distance = (data['distance_km'] ?? 0.0) as num;
                      final cost = (data['estimated_cost'] ?? 0.0) as num;

                      final Timestamp? startTs = data['startTime'] as Timestamp?;
                      final dateStr = startTs != null
                          ? DateFormat('dd MMM yyyy, hh:mm a')
                          .format(startTs.toDate())
                          : 'No start time';

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 10,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 20,
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
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dateStr,
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Mode: $mode',
                                    style: TextStyle(
                                      color: Colors.blue.shade700,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'Distance: ${distance.toStringAsFixed(1)} km',
                                    style: const TextStyle(
                                      color: Color(0xFF4B5563),
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Cost: ₹${cost.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Color(0xFF4B5563),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFF9CA3AF),
                            ),
                            onTap: () {
                              // ▶ You can open Trip Detail Page here later
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
