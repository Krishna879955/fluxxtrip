import 'package:share_plus/share_plus.dart';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'admin_trip_detail_page.dart';

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

  // 🔹 NEW: user email filter state
  String? _selectedUserEmail = 'All';
  List<Map<String, String>> _userList = []; // {email, uid}

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

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  // 🔹 Load users from users collection (docId = uid, field = email)
  Future<void> _fetchUsers() async {
    try {
      final snap =
      await FirebaseFirestore.instance.collection('users').get();

      setState(() {
        _userList = snap.docs.map((doc) {
          final data = doc.data();
          return {
            'uid': doc.id,
            'email': (data['email'] ?? '').toString(),
          };
        }).toList();
      });
    } catch (e) {
      debugPrint('Failed to load users for email filter: $e');
    }
  }

  // 🔹 Map createdBy uid -> email (fallback to uid if not found)
  String _getEmailForUid(String uid) {
    if (uid.isEmpty) return '';

    final user = _userList.firstWhere(
          (u) => u['uid'] == uid,
      orElse: () => {'uid': '', 'email': ''},
    );

    final email = user['email'] ?? '';
    return email.isNotEmpty ? email : uid;
  }

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

  // 🔹 Apply filters (mode/purpose/status/email) in Dart
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

      // 🔹 user email filter (using createdBy uid -> email from _userList)
      if (_selectedUserEmail != null && _selectedUserEmail != 'All') {
        final createdBy = (data['createdBy'] ?? '').toString();

        final user = _userList.firstWhere(
              (u) => u['uid'] == createdBy,
          orElse: () => {'uid': '', 'email': ''},
        );

        final email = user['email'] ?? '';
        if (email != _selectedUserEmail) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  // 🔹 CSV Export (uses same filters)
  Future<void> _exportTripsToCsv() async {
    try {
      final querySnapshot = await _buildBaseQuery().get();
      final filteredDocs = _applyInMemoryFilters(querySnapshot.docs);

      if (filteredDocs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No trips to export for current filters')),
        );
        return;
      }

      final buffer = StringBuffer();
      final csvDateFormat = DateFormat('dd/MM/yy, HH:mm');

      String fmtTs(dynamic ts) {
        if (ts is Timestamp) return csvDateFormat.format(ts.toDate());
        return '';
      }

      // Header
      buffer.writeln([
        'user_name',
        'Trip_number',
        'Origin_latitude',
        'Origin_longitude',
        'Destination_latitude',
        'Destination_longitude',
        'Number_of_Companions',
        'Cost_of_Trip',
        'Start_Time(dd/mm/yy, hh:mm)',
        'End_Time(dd/mm/yy, hh:mm)',
        'Mode_of_Transport',
        'Purpose_of_Trip',
        'Trip_Type',
      ].join(','));

      for (final doc in filteredDocs) {
        final data = doc.data();

        // 🔹 Use email from uid when possible
        final createdByUid = (data['createdBy'] ?? '').toString();
        final userNameField = (data['user_name'] ?? '').toString();
        final userEmail = _getEmailForUid(createdByUid);

        final userName = userNameField.isNotEmpty
            ? userNameField
            : (userEmail.isNotEmpty ? userEmail : createdByUid);

        final rawTripNumber = data['trip_number'] ?? data['tripNumber'];
        final tripNumber =
        (rawTripNumber ?? doc.id.substring(0, 6).toUpperCase())
            .toString();

        final originLat = (data['origin_latitude'] as num?)?.toDouble();
        final originLng = (data['origin_longitude'] as num?)?.toDouble();
        final destLat = (data['destination_latitude'] as num?)?.toDouble();
        final destLng = (data['destination_longitude'] as num?)?.toDouble();

        final numCompanions = (data['num_companions'] as num?)?.toInt() ?? 0;

        double totalCost = 0.0;
        if (data.containsKey('total_cost')) {
          totalCost = (data['total_cost'] as num?)?.toDouble() ?? 0.0;
        } else if (data.containsKey('estimated_cost')) {
          totalCost = (data['estimated_cost'] as num?)?.toDouble() ?? 0.0;
        } else if (data.containsKey('cost_per_person')) {
          final cpp = (data['cost_per_person'] as num?)?.toDouble() ?? 0.0;
          totalCost = cpp * numCompanions;
        }

        final startTimeStr = fmtTs(data['startTime']);
        final endTimeStr = fmtTs(data['endTime']);

        final mode = (data['mode'] ?? '').toString();
        final purpose = (data['purpose'] ?? '').toString();
        final tripType = (data['tripType'] ?? 'FormCapture').toString();

        buffer.writeln([
          userName,
          tripNumber,
          originLat?.toString() ?? '',
          originLng?.toString() ?? '',
          destLat?.toString() ?? '',
          destLng?.toString() ?? '',
          numCompanions.toString(),
          totalCost.toStringAsFixed(2),
          startTimeStr,
          endTimeStr,
          mode,
          purpose,
          tripType,
        ].join(','));
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/trips_export_filtered.csv');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Filtered Trip Export CSV - Upload to Drive',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV exported successfully!')),
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

  // 🔹 UPDATE trip
  Future<void> _updateTrip(
      String tripId, Map<String, dynamic> updates) async {
    try {
      await FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .update(updates);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: Colors.redAccent),
      );
    }
  }

  // 🔹 DELETE trip with confirmation
  Future<void> _confirmDeleteTrip(String tripId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete trip?'),
        content: const Text(
            'This action cannot be undone. Do you want to delete this trip?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('trips')
            .doc(tripId)
            .delete();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip deleted')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // 🔹 UI to edit a trip (simple fields)
  Future<void> _showEditTripSheet(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final TextEditingController costCtrl = TextEditingController(
        text: (data['estimated_cost'] ?? data['total_cost'] ?? '')
            .toString());
    final TextEditingController distanceCtrl = TextEditingController(
        text: (data['distance_km'] ?? '').toString());
    String status = (data['status'] ?? 'Pending').toString();
    String mode = (data['mode'] ?? '').toString();
    String purpose = (data['purpose'] ?? '').toString();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding:
          EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('Edit Trip',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16))),
                    IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 8),

                // Status
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: _statuses
                      .where((s) => s != 'All')
                      .map((s) =>
                      DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => status = v ?? status,
                ),
                const SizedBox(height: 8),

                // Mode
                DropdownButtonFormField<String>(
                  value: mode.isEmpty ? null : mode,
                  decoration: const InputDecoration(
                      labelText: 'Mode',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: _modes
                      .where((m) => m != 'All')
                      .map((m) =>
                      DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => mode = v ?? mode,
                ),
                const SizedBox(height: 8),

                // Purpose
                DropdownButtonFormField<String>(
                  value: purpose.isEmpty ? null : purpose,
                  decoration: const InputDecoration(
                      labelText: 'Purpose',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: _purposes
                      .where((p) => p != 'All')
                      .map((p) =>
                      DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => purpose = v ?? purpose,
                ),
                const SizedBox(height: 8),

                TextField(
                    controller: distanceCtrl,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Distance (km)',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 8),
                TextField(
                    controller: costCtrl,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Cost (₹)',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final updates = <String, dynamic>{};
                          if (status.isNotEmpty) updates['status'] = status;
                          if (mode.isNotEmpty) updates['mode'] = mode;
                          if (purpose.isNotEmpty) {
                            updates['purpose'] = purpose;
                          }

                          final parsedDistance =
                          double.tryParse(distanceCtrl.text);
                          if (parsedDistance != null) {
                            updates['distance_km'] = parsedDistance;
                          }

                          final parsedCost =
                          double.tryParse(costCtrl.text);
                          if (parsedCost != null) {
                            updates['estimated_cost'] = parsedCost;
                          }

                          Navigator.of(ctx).pop();
                          _updateTrip(doc.id, updates);
                        },
                        child: const Text('Save changes'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
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
      elevation: 2,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  'Filters',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Icon(Icons.tune, size: 18, color: Color(0xFF6B7280)),
              ],
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
                        .map((m) => DropdownMenuItem<String>(
                        value: m, child: Text(m)))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedMode = value;
                      });
                    },
                    elevation: 0,
                    dropdownColor: Colors.white,
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
                        .map((p) => DropdownMenuItem<String>(
                        value: p, child: Text(p)))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedPurpose = value;
                      });
                    },
                    elevation: 0,
                    dropdownColor: Colors.white,
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
                        .map((s) => DropdownMenuItem<String>(
                        value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedStatus = value;
                      });
                    },
                    elevation: 0,
                    dropdownColor: Colors.white,
                  ),
                ),

                // User Email dropdown
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    value: _selectedUserEmail,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'User Email',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'All',
                        child: Text(
                          'All users',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ..._userList.map(
                            (u) => DropdownMenuItem<String>(
                          value: u['email'],
                          child: Text(
                            u['email'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedUserEmail = value;
                      });
                    },
                    elevation: 0,
                    dropdownColor: Colors.white,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Date range + clear
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final initialDateRange = _selectedDateRange ??
                        DateTimeRange(
                          start:
                          now.subtract(const Duration(days: 7)),
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

                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedMode = 'All';
                      _selectedPurpose = 'All';
                      _selectedStatus = 'All';
                      _selectedDateRange = null;
                      _selectedUserEmail = 'All';
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

  // 🔹 Summary cards
  Widget _buildStatsSummary({
    required int totalTrips,
    required double totalDistanceKm,
    required Map<String, int> statusCounts,
    required int liveTrips,
    required int manualTrips,
  }) {
    final verified = statusCounts['Verified'] ?? 0;
    final pending = statusCounts['Pending'] ?? 0;
    final invalid = statusCounts['Invalid'] ?? 0;

    return SizedBox(
      height: 130,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          _StatCard(
            title: 'Total Trips',
            value: '$totalTrips',
            subtitle: 'Current filters',
            icon: Icons.route,
            color: const Color(0xFF2563EB),
          ),
          _StatCard(
            title: 'Distance (km)',
            value: totalDistanceKm.toStringAsFixed(1),
            subtitle: 'All trips',
            icon: Icons.social_distance,
            color: const Color(0xFF10B981),
          ),
          _StatCard(
            title: 'Status',
            value: '$verified ✓',
            subtitle: 'Pending: $pending | Inv: $invalid',
            icon: Icons.verified,
            color: const Color(0xFF6366F1),
          ),
          _StatCard(
            title: 'Live vs Manual',
            value: '$liveTrips',
            subtitle: 'Live: $liveTrips | Form: $manualTrips',
            icon: Icons.sensors,
            color: const Color(0xFF14B8A6),
          ),
        ],
      ),
    );
  }

  // 🔹 Simple bar chart (Trips per day)
  Widget _buildTripsPerDayChart(Map<String, int> tripsPerDay) {
    if (tripsPerDay.isEmpty) {
      return const SizedBox.shrink();
    }

    final entries = tripsPerDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxCount =
    entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trips per Day',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final e in entries)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: 14,
                                height: maxCount == 0
                                    ? 0
                                    : (e.value / maxCount) * 60,
                                decoration: BoxDecoration(
                                  borderRadius:
                                  BorderRadius.circular(6),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF2563EB),
                                      Color(0xFF60A5FA),
                                    ],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            e.key,
                            style: const TextStyle(
                                fontSize: 9,
                                color: Color(0xFF6B7280)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔹 Mode distribution chart (horizontal bars)
  Widget _buildModeDistributionChart(Map<String, int> modeCounts) {
    if (modeCounts.isEmpty) return const SizedBox.shrink();

    final entries = modeCounts.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) return const SizedBox.shrink();

    final maxCount = entries
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mode Distribution',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                for (final e in entries)
                  Padding(
                    padding:
                    const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 70,
                          child: Text(e.key,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF4B5563))),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius:
                            BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: maxCount == 0
                                  ? 0
                                  : e.value.toDouble() / maxCount,
                              minHeight: 6,
                              backgroundColor:
                              const Color(0xFFE5E7EB),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(e.value.toString(),
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF6B7280))),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 🔹 Live vs Manual card
  Widget _buildTripTypeDistributionCard(
      Map<String, int> tripTypeCounts) {
    if (tripTypeCounts.isEmpty) return const SizedBox.shrink();

    final live = tripTypeCounts['LiveTracking'] ?? 0;
    final manual = (tripTypeCounts['FormCapture'] ?? 0) +
        (tripTypeCounts['Manual'] ?? 0) +
        (tripTypeCounts[''] ?? 0);

    final total = live + manual;
    if (total == 0) return const SizedBox.shrink();

    final liveRatio = live / total;
    final manualRatio = manual / total;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Trip Capture Type',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    Expanded(
                      flex: (liveRatio * 1000)
                          .round()
                          .clamp(0, 1000),
                      child: Container(
                          color: const Color(0xFF14B8A6)),
                    ),
                    Expanded(
                      flex: (manualRatio * 1000)
                          .round()
                          .clamp(0, 1000),
                      child: Container(
                          color: const Color(0xFFE5E7EB)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Row(
                  children: const [
                    CircleAvatar(
                        radius: 4,
                        backgroundColor: Color(0xFF14B8A6)),
                    SizedBox(width: 4),
                    Text('Live tracking: ',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF4B5563))),
                  ],
                ),
                Text('$live',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF4B5563))),
                const SizedBox(width: 12),
                Row(
                  children: const [
                    CircleAvatar(
                        radius: 4,
                        backgroundColor: Color(0xFFE5E7EB)),
                    SizedBox(width: 4),
                    Text('Manual / Form: ',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF4B5563))),
                  ],
                ),
                Text('$manual',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF4B5563))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 🔹 Trip card (single trip) – now shows companion emails + user email
  Widget _buildTripCard(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final Timestamp? startTs = data['startTime'] as Timestamp?;
    final Timestamp? endTs = data['endTime'] as Timestamp?;

    final origin = data['originPlace'] ?? 'Origin';
    final dest = data['destinationPlace'] ?? 'Destination';
    final mode = data['mode'] ?? 'Mode';
    final distanceKm = (data['distance_km'] ?? 0).toString();
    final cost =
    (data['estimated_cost'] ?? data['total_cost'] ?? 0).toString();
    final createdBy = data['createdBy'] ?? '';

    final status = (data['status'] ?? 'Pending').toString();
    final String tripType =
    (data['tripType'] ?? 'FormCapture').toString();
    final bool isLive = tripType == 'LiveTracking';

    int? durationMinutes;
    if (startTs != null && endTs != null) {
      durationMinutes =
          endTs.toDate().difference(startTs.toDate()).inMinutes;
    }

    // Companions
    final rawCompanions = data['companions_details'];
    final List<dynamic> companions =
    rawCompanions is List ? rawCompanions : const [];
    final numCompanions = companions.length;

    // Companion emails or names
    final companionEmails = companions
        .whereType<Map>()
        .map((c) {
      final email = (c['email'] ?? '').toString().trim();
      final name = (c['name'] ?? '').toString().trim();
      return email.isNotEmpty ? email : name;
    })
        .where((v) => v.isNotEmpty)
        .toList();

    // Created by email
    final createdByEmail = _getEmailForUid(createdBy.toString());

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
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AdminTripDetailPage(tripId: doc.id),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.directions,
                      size: 18, color: Color(0xFF2563EB)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$origin → $dest',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: statusBg,
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: statusText),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),
              Text(
                'Mode: $mode • Distance: $distanceKm km • ₹$cost',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF4B5563)),
              ),

              // Companions summary
              if (companionEmails.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Companions: ${companionEmails.length} • '
                      '${companionEmails.take(2).join(", ")}'
                      '${companionEmails.length > 2 ? " +" : ""}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ],

              const SizedBox(height: 4),
              Text(
                'Start: ${startTs != null ? dateFormat.format(startTs.toDate()) : 'N/A'}',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF6B7280)),
              ),
              Text(
                'End:   ${endTs != null ? dateFormat.format(endTs.toDate()) : 'N/A'}',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF6B7280)),
              ),

              if (durationMinutes != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Duration: $durationMinutes min',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF6B7280)),
                ),
              ],

              const SizedBox(height: 4),
              Text(
                'User: $createdByEmail',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF9CA3AF)),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 1,
        titleSpacing: 0,
        title: const Text('Admin Dashboard',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _exportTripsToCsv,
              tooltip: 'Export filtered trips CSV',
              icon: const Icon(Icons.download_rounded)),
          IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: _logout),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildBaseQuery().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF2563EB)));
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'Error loading trips:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 14),
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData ||
                    snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No trips found for current filters.',
                      style: TextStyle(
                          color: Color(0xFF6B7280), fontSize: 14),
                    ),
                  );
                }

                final filteredDocs =
                _applyInMemoryFilters(snapshot.data!.docs);

                if (filteredDocs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No trips match the selected filters.',
                      style: TextStyle(
                          color: Color(0xFF6B7280), fontSize: 14),
                    ),
                  );
                }

                int totalTrips = filteredDocs.length;
                double totalDistanceKm = 0;

                final Map<String, int> statusCounts = {};
                final Map<String, int> modeCounts = {};
                final Map<String, int> tripsPerDay = {};
                final Map<String, int> tripTypeCounts = {};

                int liveTrips = 0;
                int manualTrips = 0;

                for (final doc in filteredDocs) {
                  final data = doc.data();

                  final distance =
                      (data['distance_km'] as num?)?.toDouble() ?? 0.0;
                  totalDistanceKm += distance;

                  final status =
                  (data['status'] ?? 'Pending').toString();
                  statusCounts[status] =
                      (statusCounts[status] ?? 0) + 1;

                  final mode =
                  (data['mode'] ?? 'Unknown').toString();
                  modeCounts[mode] =
                      (modeCounts[mode] ?? 0) + 1;

                  final String tripType =
                  (data['tripType'] ?? 'FormCapture')
                      .toString();
                  tripTypeCounts[tripType] =
                      (tripTypeCounts[tripType] ?? 0) + 1;
                  if (tripType == 'LiveTracking') {
                    liveTrips++;
                  } else {
                    manualTrips++;
                  }

                  final Timestamp? startTs =
                  data['startTime'] as Timestamp?;
                  if (startTs != null) {
                    final label = _filterDateFormat
                        .format(startTs.toDate());
                    tripsPerDay[label] =
                        (tripsPerDay[label] ?? 0) + 1;
                  }
                }

                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                        children: [
                          _buildStatsSummary(
                            totalTrips: totalTrips,
                            totalDistanceKm: totalDistanceKm,
                            statusCounts: statusCounts,
                            liveTrips: liveTrips,
                            manualTrips: manualTrips,
                          ),
                          _buildTripsPerDayChart(tripsPerDay),
                          _buildModeDistributionChart(modeCounts),
                          _buildTripTypeDistributionCard(
                              tripTypeCounts),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(
                                16, 10, 16, 4),
                            child: Text(
                              'Trips',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Color(0xFF111827)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          16, 4, 16, 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                              (context, index) {
                            return _buildTripCard(
                                filteredDocs[index]);
                          },
                          childCount: filteredDocs.length,
                        ),
                      ),
                    ),
                  ],
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

// 🔹 Small reusable stat card
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _StatCard(
      {Key? key,
        required this.title,
        required this.value,
        required this.subtitle,
        required this.icon,
        required this.color})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }
}
