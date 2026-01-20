import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // 👈 added for peak hour formatting

class UserDashboard extends StatefulWidget {
  const UserDashboard({Key? key}) : super(key: key);

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  final User? _user = FirebaseAuth.instance.currentUser;

  /// Rough CO₂ factors in kg/km for each mode
  static const Map<String, double> _co2PerKm = {
    'Car': 0.18,
    'Taxi': 0.18,
    'Motorcycle': 0.09,
    'Bus': 0.08,
    'Train': 0.04,
    'Metro': 0.04,
    'Bicycle': 0.0,
    'Walk': 0.0,
    'Other': 0.12,
  };

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    // AuthWrapper will pick this up and show LoginPage.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Your Travel Insights',
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF111827)),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('trips')
            .where('createdBy', isEqualTo: _user?.uid)
        // no orderBy here → avoids index error; we sort in Dart instead
            .snapshots(),
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
            return _buildEmptyState();
          }

          // ---- Prepare data & stats ----
          final docs = snapshot.data!.docs;

          // sort by startTime descending
          docs.sort((a, b) {
            final at = a.data()['startTime'] is Timestamp
                ? (a.data()['startTime'] as Timestamp).toDate()
                : DateTime(0);
            final bt = b.data()['startTime'] is Timestamp
                ? (b.data()['startTime'] as Timestamp).toDate()
                : DateTime(0);
            return bt.compareTo(at);
          });

          final weeklyData = _prepareWeeklyBarData(docs);
          final modeData = _prepareModePieData(docs);

          // Summary numbers
          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);
          final todayEnd = todayStart.add(const Duration(days: 1));

          double todayDistance = 0;
          double totalDistance = 0;
          double totalCost = 0;
          double totalCo2 = 0;
          int totalTrips = docs.length;

          for (final doc in docs) {
            final data = doc.data();
            final distance = (data['distance_km'] ?? 0).toDouble();
            final cost = (data['estimated_cost'] ?? 0).toDouble();
            final mode = (data['mode'] as String?) ?? 'Other';

            totalDistance += distance;
            totalCost += cost;
            totalCo2 += distance * (_co2PerKm[mode] ?? _co2PerKm['Other']!);

            final ts = data['startTime'] as Timestamp?;
            final dt = ts?.toDate();
            if (dt != null && dt.isAfter(todayStart) && dt.isBefore(todayEnd)) {
              todayDistance += distance;
            }
          }

          // 👇 NEW: Peak hour label (e.g. "Peak hour: 6–7 PM • 4 trips")
          final String? peakLabel = _computePeakHourLabel(docs);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroBanner(),
                const SizedBox(height: 16),
                _buildSummaryRow(
                  todayDistanceKm: todayDistance,
                  totalTrips: totalTrips,
                  totalCo2Kg: totalCo2,
                  totalCost: totalCost,
                ),
                const SizedBox(height: 8),

                // 👇 Show peak hour line (only if we have data)
                if (peakLabel != null) ...[
                  Text(
                    peakLabel,
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                _buildQuickActionsRow(context),
                const SizedBox(height: 20),
                _buildChartCard(
                  'Weekly Travel Frequency',
                  _buildBarChart(weeklyData),
                ),
                const SizedBox(height: 20),
                _buildChartCard(
                  'Travel Mode Distribution',
                  _buildPieChart(modeData),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ========== EMPTY STATE ==========

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildHeroBanner(),
          const SizedBox(height: 24),
          const Icon(
            Icons.travel_explore_rounded,
            size: 72,
            color: Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 16),
          const Text(
            'No trip data yet',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Capture your first trip to start seeing insights about your travel habits.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          _buildQuickActionsRow(context),
        ],
      ),
    );
  }

  // ========== UI BUILDERS ==========

  Widget _buildHeroBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF10B981)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white24,
            child: Icon(Icons.travel_explore_rounded,
                size: 26, color: Colors.white),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready to travel?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Tap any action below to capture or explore your trips.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow({
    required double todayDistanceKm,
    required int totalTrips,
    required double totalCo2Kg,
    required double totalCost,
  }) {
    String formatDouble(double v) => v.toStringAsFixed(v >= 100 ? 0 : 2);

    return Row(
      children: [
        Expanded(
          child: _smallStatCard(
            icon: Icons.timeline_rounded,
            iconBg: const Color(0xFFE0F2FE),
            iconColor: const Color(0xFF2563EB),
            label: 'Today distance',
            value: '${formatDouble(todayDistanceKm)} km',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _smallStatCard(
            icon: Icons.flag_rounded,
            iconBg: const Color(0xFFE5E7EB),
            iconColor: const Color(0xFF4B5563),
            label: 'Trips saved',
            value: '$totalTrips',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _smallStatCard(
            icon: Icons.eco_rounded,
            iconBg: const Color(0xFFDCFCE7),
            iconColor: const Color(0xFF16A34A),
            label: 'Total CO₂',
            value: '${formatDouble(totalCo2Kg)} kg',
          ),
        ),
      ],
    );
  }

  Widget _smallStatCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsRow(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _quickActionButton(
          icon: Icons.add_location_alt_outlined,
          label: 'Capture Trip',
          onTap: () => Navigator.pushNamed(context, '/trip_capture'),
          primary: true,
        ),
        _quickActionButton(
          icon: Icons.history_rounded,
          label: 'Trip History',
          onTap: () => Navigator.pushNamed(context, '/trip_history'),
        ),
        _quickActionButton(
          icon: Icons.alt_route_rounded,
          label: 'End-to-End',
          onTap: () => Navigator.pushNamed(context, '/end_to_end'),
        ),
        _quickActionButton(
          icon: Icons.directions_transit_filled_rounded,
          label: 'Smart Transit',
          onTap: () => Navigator.pushNamed(context, '/smart_transit'),
        ),
        _quickActionButton(
          icon: Icons.my_location_rounded,
          label: 'Live Tracking (Auto)',
          onTap: () => Navigator.pushNamed(context, '/live_tracking'),
        ),
        _quickActionButton(
          icon: Icons.directions_bus_filled_rounded,
          label: 'Smart Transit',
          onTap: () => Navigator.pushNamed(context, '/smart_transit'),
        ),

      ],
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 16 * 2 - 12 * 3) / 2,
      child: Material(
        color: primary ? const Color(0xFF2563EB) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: primary ? 3 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: primary ? Colors.white : const Color(0xFF2563EB),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                      primary ? Colors.white : const Color(0xFF2563EB),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard(String title, Widget chart) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  size: 18, color: Color(0xFF2563EB)),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(height: 200, child: chart),
        ],
      ),
    );
  }

  // ========== DATA HELPERS ==========

  Map<int, double> _prepareWeeklyBarData(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> trips,
      ) {
    final Map<int, double> data = {
      1: 0,
      2: 0,
      3: 0,
      4: 0,
      5: 0,
      6: 0,
      7: 0,
    };

    for (final doc in trips) {
      final trip = doc.data();
      final Timestamp? startTime = trip['startTime'] as Timestamp?;
      if (startTime != null) {
        final day = startTime.toDate().weekday; // 1–7
        data[day] = (data[day] ?? 0) + 1;
      }
    }
    return data;
  }

  Map<String, double> _prepareModePieData(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> trips,
      ) {
    final Map<String, double> data = {};

    for (final doc in trips) {
      final trip = doc.data();
      final String mode = (trip['mode'] as String?) ?? 'Other';
      data[mode] = (data[mode] ?? 0) + 1;
    }

    return data;
  }

  Widget _buildBarChart(Map<int, double> data) {
    final maxValue =
    data.values.fold<double>(0.0, (max, v) => v > max ? v : max);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxValue == 0 ? 1 : maxValue) + 1,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                rod.toY.toString(),
                const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: _buildBottomDayTitle,
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: _buildLeftTitle,
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: const Color(0xFFE5E7EB),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: data.entries
            .map(
              (entry) => BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value,
                color: const Color(0xFF2563EB),
                width: 16,
                borderRadius: BorderRadius.circular(6),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: (maxValue == 0 ? 1 : maxValue) + 1,
                  color: const Color(0xFFE5E7EB),
                ),
              ),
            ],
          ),
        )
            .toList(),
      ),
    );
  }

  static Widget _buildBottomDayTitle(double value, TitleMeta meta) {
    const style = TextStyle(color: Color(0xFF6B7280), fontSize: 11);
    String text;
    switch (value.toInt()) {
      case 1:
        text = 'M';
        break;
      case 2:
        text = 'T';
        break;
      case 3:
        text = 'W';
        break;
      case 4:
        text = 'T';
        break;
      case 5:
        text = 'F';
        break;
      case 6:
        text = 'S';
        break;
      case 7:
        text = 'S';
        break;
      default:
        text = '';
    }
    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 4,
      child: Text(text, style: style),
    );
  }

  static Widget _buildLeftTitle(double value, TitleMeta meta) {
    if (value % 1 != 0) return const SizedBox.shrink();
    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 4,
      child: Text(
        value.toInt().toString(),
        style: const TextStyle(
          color: Color(0xFF6B7280),
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildPieChart(Map<String, double> data) {
    if (data.isEmpty) {
      return const Center(
        child: Text(
          'No data',
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
      );
    }

    final List<Color> colors = const [
      Color(0xFF2563EB),
      Color(0xFF10B981),
      Color(0xFFF97316),
      Color(0xFF8B5CF6),
      Color(0xFFEF4444),
      Color(0xFF0EA5E9),
    ];
    int colorIndex = 0;

    return PieChart(
      PieChartData(
        sections: data.entries.map((entry) {
          final color = colors[colorIndex++ % colors.length];
          return PieChartSectionData(
            color: color,
            value: entry.value,
            title: '${entry.key}\n(${entry.value.toInt()})',
            radius: 80,
            titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            titlePositionPercentageOffset: 0.7,
          );
        }).toList(),
        sectionsSpace: 2,
        centerSpaceRadius: 34,
      ),
    );
  }

  // ========== PEAK HOUR HELPERS ==========

  /// Compute a human-readable peak hour label from recent trips.
  /// Example: "Peak hour: 6–7 PM • 4 trips"
  String? _computePeakHourLabel(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> trips,
      ) {
    // 24 buckets for hours 0..23
    final List<int> counts = List<int>.filled(24, 0);

    for (final doc in trips) {
      final data = doc.data();
      final ts = data['startTime'] as Timestamp?;
      if (ts == null) continue;

      final dt = ts.toDate();
      final hour = dt.hour; // 0–23
      if (hour >= 0 && hour < 24) {
        counts[hour] = counts[hour] + 1;
      }
    }

    int maxHour = -1;
    int maxCount = 0;

    for (int h = 0; h < 24; h++) {
      if (counts[h] > maxCount) {
        maxCount = counts[h];
        maxHour = h;
      }
    }

    if (maxHour == -1 || maxCount == 0) {
      return null; // no trips with startTime
    }

    final startLabel = _formatHourLabel(maxHour);
    final endLabel = _formatHourLabel((maxHour + 1) % 24);

    return 'Peak hour: $startLabel – $endLabel • $maxCount trips';
  }

  /// Format hour (0–23) like "6 AM", "7 PM"
  String _formatHourLabel(int hour) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, hour);
    return DateFormat('h a').format(dt);
  }
}
