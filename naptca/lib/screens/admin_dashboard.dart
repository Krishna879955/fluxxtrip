import 'package:share_plus/share_plus.dart';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final dateFormat = DateFormat('dd MMM yyyy, HH:mm');
  final _filterDateFormat = DateFormat('dd MMM');

  // 🔹 Filter state
  String? _selectedMode = 'All';
  String? _selectedPurpose = 'All';
  String? _selectedStatus = 'All';
  DateTimeRange? _selectedDateRange;

  // 🔹 Filter option lists
  final List<String> _modes = <String>[
    'All',
    'Bus',
    'Car',
    'Bike',
    'Walk',
    'Metro',
    'Auto',
    'Train',
    'Other',
  ];

  final List<String> _purposes = <String>[
    'All',
    'Work',
    'Education',
    'Shopping',
    'Leisure',
    'Health',
    'Personal',
    'Other',
  ];

  final List<String> _statuses = <String>[
    'All',
    'Pending',
    'Verified',
    'Invalid',
    'Flagged',
  ];

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  // 🔹 BASE Firestore query (only date range + ordering)
  Query<Map<String, dynamic>> _buildBaseQuery() {
    Query<Map<String, dynamic>> q =
    FirebaseFirestore.instance.collection('trips');

    if (_selectedDateRange != null) {
      final start = Timestamp.fromDate(_selectedDateRange!.start);
      final end = Timestamp.fromDate(
        _selectedDateRange!.end.add(const Duration(days: 1)),
      );
      q = q
          .where('startTime', isGreaterThanOrEqualTo: start)
          .where('startTime', isLessThan: end)
          .orderBy('startTime', descending: true);
    } else {
      q = q.orderBy('createdAt', descending: true);
    }

    return q;
  }

  // 🔹 Apply filters (mode/purpose/status) in Dart
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyInMemoryFilters(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    return docs.where((doc) {
      final data = doc.data();

      // mode filter
      if (_selectedMode != null &&
          _selectedMode != 'All' &&
          data['mode'] != _selectedMode) {
        return false;
      }

      // purpose filter
      if (_selectedPurpose != null &&
          _selectedPurpose != 'All' &&
          data['purpose'] != _selectedPurpose) {
        return false;
      }

      // status filter
      if (_selectedStatus != null &&
          _selectedStatus != 'All' &&
          (data['status'] ?? 'Pending') != _selectedStatus) {
        return false;
      }

      return true;
    }).toList();
  }

  // 🔹 CSV Export (uses same filters)
  Future<void> _exportTripsToCsv() async {
    try {
      final querySnapshot = await _buildBaseQuery().get();

      // Apply same filters in memory
      final filteredDocs = _applyInMemoryFilters(querySnapshot.docs);

      if (filteredDocs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No trips to export for current filters'),
          ),
        );
        return;
      }

      final buffer = StringBuffer();

      // CSV header
      buffer.writeln([
        'trip_id',
        'createdBy',
        'originPlace',
        'destinationPlace',
        'startTime',
        'endTime',
        'mode',
        'purpose',
        'distance_km',
        'estimated_cost',
        'co2_kg',          // optional
        'duration_minutes',// computed
        'status',          // optional
        'createdAt',
      ].join(','));

      for (final doc in filteredDocs) {
        final data = doc.data();

        String fmt(dynamic ts) =>
            (ts is Timestamp) ? dateFormat.format(ts.toDate()) : '';

        final Timestamp? startTs = data['startTime'] as Timestamp?;
        final Timestamp? endTs = data['endTime'] as Timestamp?;

        int? durationMinutes;
        if (startTs != null && endTs != null) {
          durationMinutes =
              endTs.toDate().difference(startTs.toDate()).inMinutes;
        }

        final co2 = (data['co2_kg'] ?? '').toString(); // change if needed
        final status = (data['status'] ?? '').toString();

        buffer.writeln([
          doc.id,
          data['createdBy'] ?? '',
          data['originPlace'] ?? '',
          data['destinationPlace'] ?? '',
          fmt(data['startTime']),
          fmt(data['endTime']),
          data['mode'] ?? '',
          data['purpose'] ?? '',
          (data['distance_km'] ?? '').toString(),
          (data['estimated_cost'] ?? '').toString(),
          co2,
          durationMinutes?.toString() ?? '',
          status,
          fmt(data['createdAt']),
        ].join(','));
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/trips_export_filtered.csv');

      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path)],
        text:
        'Filtered Trip Export CSV (based on current dashboard filters) - Upload to Drive',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Filtered CSV ready — choose Drive to upload'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // 🔹 Filter bar UI
  Widget _buildFilterBar() {
    final String dateRangeLabel;
    if (_selectedDateRange == null) {
      dateRangeLabel = 'Date range';
    } else {
      dateRangeLabel =
      '${_filterDateFormat.format(_selectedDateRange!.start)} - ${_filterDateFormat.format(_selectedDateRange!.end)}';
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filters',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Mode dropdown
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    value: _selectedMode,
                    decoration: const InputDecoration(
                      labelText: 'Mode',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _modes
                        .map(
                          (m) => DropdownMenuItem<String>(
                        value: m,
                        child: Text(m),
                      ),
                    )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedMode = value;
                      });
                    },
                  ),
                ),

                // Purpose dropdown
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    value: _selectedPurpose,
                    decoration: const InputDecoration(
                      labelText: 'Purpose',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _purposes
                        .map(
                          (p) => DropdownMenuItem<String>(
                        value: p,
                        child: Text(p),
                      ),
                    )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedPurpose = value;
                      });
                    },
                  ),
                ),

                // Status dropdown
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    value: _selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _statuses
                        .map(
                          (s) => DropdownMenuItem<String>(
                        value: s,
                        child: Text(s),
                      ),
                    )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedStatus = value;
                      });
                    },
                  ),
                ),

                // Date range picker
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final initialDateRange = _selectedDateRange ??
                        DateTimeRange(
                          start: now.subtract(const Duration(days: 7)),
                          end: now,
                        );

                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDateRange: initialDateRange,
                    );

                    if (picked != null) {
                      setState(() {
                        _selectedDateRange = picked;
                      });
                    }
                  },
                  icon: const Icon(Icons.date_range),
                  label: Text(dateRangeLabel),
                ),

                // Clear filters
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedMode = 'All';
                      _selectedPurpose = 'All';
                      _selectedStatus = 'All';
                      _selectedDateRange = null;
                    });
                  },
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            onPressed: _exportTripsToCsv,
            tooltip: 'Export filtered trips CSV',
            icon: const Icon(Icons.download_rounded),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildBaseQuery().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2563EB)),
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

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No trips found for current filters.',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
                      ),
                    ),
                  );
                }

                // ✅ Apply filters in Dart
                final filteredDocs =
                _applyInMemoryFilters(snapshot.data!.docs);

                if (filteredDocs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No trips match the selected filters.',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final data = filteredDocs[index].data();
                    final Timestamp? startTs = data['startTime'] as Timestamp?;
                    final Timestamp? endTs = data['endTime'] as Timestamp?;

                    final origin = data['originPlace'] ?? 'Origin';
                    final dest = data['destinationPlace'] ?? 'Destination';
                    final mode = data['mode'] ?? 'Mode';
                    final distance = (data['distance_km'] ?? 0).toString();
                    final cost = (data['estimated_cost'] ?? 0).toString();
                    final createdBy = data['createdBy'] ?? '';

                    final co2 = (data['co2_kg'] ?? 0).toString();
                    final status = (data['status'] ?? 'Pending').toString();

                    int? durationMinutes;
                    if (startTs != null && endTs != null) {
                      durationMinutes =
                          endTs.toDate().difference(startTs.toDate()).inMinutes;
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$origin → $dest',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Mode: $mode • Distance: $distance km • ₹$cost',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Start: ${startTs != null ? dateFormat.format(startTs.toDate()) : 'N/A'}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            Text(
                              'End:   ${endTs != null ? dateFormat.format(endTs.toDate()) : 'N/A'}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            if (durationMinutes != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Duration: $durationMinutes min',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'User: $createdBy',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF9CA3AF),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (co2 != '0')
                                  Text(
                                    'CO₂: $co2 kg',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF10B981),
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
                                    color: status == 'Verified'
                                        ? const Color(0xFFD1FAE5)
                                        : status == 'Invalid'
                                        ? const Color(0xFFFEE2E2)
                                        : const Color(0xFFE5E7EB),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: status == 'Verified'
                                          ? const Color(0xFF047857)
                                          : status == 'Invalid'
                                          ? const Color(0xFFB91C1C)
                                          : const Color(0xFF4B5563),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _exportTripsToCsv,
        icon: const Icon(Icons.download_rounded),
        label: const Text('Export CSV'),
        backgroundColor: const Color(0xFF2563EB),
      ),
    );
  }
}
