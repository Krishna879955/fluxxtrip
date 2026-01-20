import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart'; // For PlatformException

import '../widgets/trip_form.dart';

class TripCapture extends StatefulWidget {
  const TripCapture({Key? key}) : super(key: key);

  @override
  _TripCaptureState createState() => _TripCaptureState();
}

class GenderField extends StatelessWidget {
  final String? value;
  final void Function(String?) onChanged;

  const GenderField({
    Key? key,
    required this.value,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final selected = await showModalBottomSheet<String>(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Select Gender',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _genderOption(ctx, 'Male'),
                  _genderOption(ctx, 'Female'),
                  _genderOption(ctx, 'Other'),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );

        if (selected != null) {
          onChanged(selected);
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Gender',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              value ?? 'Select gender',
              style: TextStyle(
                fontSize: 14,
                color: value == null
                    ? const Color(0xFF9CA3AF)
                    : const Color(0xFF111827),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down),
          ],
        ),
      ),
    );
  }

  static Widget _genderOption(BuildContext ctx, String label) {
    return ListTile(
      title: Text(label),
      onTap: () => Navigator.of(ctx).pop(label),
    );
  }
}

// ⭐ helper class to hold companion form controllers
class _CompanionFormData {
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
      'email': emailController.text.trim(),
      'age': int.tryParse(ageController.text.trim()) ?? 0,
      'gender': gender,
      'relation': relationController.text.trim(),
    };
  }
}

class _TripCaptureState extends State<TripCapture> {
  bool _isSaving = false;
  int _numCompanions = 1;

  // ⭐ list of companion forms
  final List<_CompanionFormData> _companions = [];

  // ⭐ dynamic transport modes data
  bool _isLoadingModes = true;
  final Map<String, double> _costPerKm = {};
  final Map<String, double> _avgSpeedKmph = {};
  final List<String> _availableModes = [];

  // ⭐ purposes list for dropdown
  final List<String> _purposes = <String>[
    'Work',
    'Education',
    'Shopping',
    'Leisure',
    'Health',
    'Personal',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _syncCompanionForms(); // ensure list length matches _numCompanions
    _loadTransportModes(); // load modes dynamically from Firestore
  }

  @override
  void dispose() {
    for (final c in _companions) {
      c.dispose();
    }
    super.dispose();
  }

  // 🔽 LOAD MODES FROM FIRESTORE
  Future<void> _loadTransportModes() async {
    try {
      final snapshot =
      await FirebaseFirestore.instance.collection('transport_modes').get();

      _costPerKm.clear();
      _avgSpeedKmph.clear();
      _availableModes.clear();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = (data['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        final double cost = (data['costPerKm'] is int)
            ? (data['costPerKm'] as int).toDouble()
            : (data['costPerKm'] as num?)?.toDouble() ?? 10.0;

        final double speed = (data['avgSpeedKmph'] is int)
            ? (data['avgSpeedKmph'] as int).toDouble()
            : (data['avgSpeedKmph'] as num?)?.toDouble() ?? 30.0;

        _costPerKm[name] = cost;
        _avgSpeedKmph[name] = speed;
        _availableModes.add(name);
      }

      if (_availableModes.isEmpty) {
        // fallback if no docs / misconfigured
        _showError(
          'No transport modes found in Firestore (collection: transport_modes). Using default values.',
        );
        _costPerKm.addAll({
          'Car': 14.0,
          'Taxi': 18.0,
          'Motorcycle': 3.0,
          'Bus': 1.0,
          'Train': 0.5,
          'Metro': 3.5,
          'Other': 5.0,
        });
        _avgSpeedKmph.addAll({
          'Car': 40.0,
          'Taxi': 35.0,
          'Motorcycle': 35.0,
          'Bus': 30.0,
          'Train': 50.0,
          'Metro': 32.0,
          'Other': 30.0,
        });
        _availableModes.addAll(_costPerKm.keys);
      }
    } catch (e) {
      _showError(
        'Failed to load transport modes. Please try again later.',
      );
      // minimal safe fallback
      if (_availableModes.isEmpty) {
        _costPerKm.addAll({
          'Car': 14.0,
          'Taxi': 18.0,
          'Motorcycle': 3.0,
          'Bus': 1.0,
          'Train': 0.5,
          'Metro': 3.5,
          'Other': 5.0,
        });
        _avgSpeedKmph.addAll({
          'Car': 40.0,
          'Taxi': 35.0,
          'Motorcycle': 35.0,
          'Bus': 30.0,
          'Train': 50.0,
          'Metro': 32.0,
          'Other': 30.0,
        });
        _availableModes.addAll(_costPerKm.keys);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingModes = false;
        });
      }
    }
  }

  // keep _companions length in sync with _numCompanions
  void _syncCompanionForms() {
    while (_companions.length < _numCompanions) {
      _companions.add(_CompanionFormData());
    }
    while (_companions.length > _numCompanions) {
      _companions.removeLast().dispose();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<Location?> _geocodeAddress(String address, String addressType) async {
    try {
      List<Location> locations = await locationFromAddress(address);
      if (locations.isEmpty) {
        _showError(
          'Could not find the $addressType location for: "$address". Please check the address.',
        );
        return null;
      }
      return locations.first;
    } on NoResultFoundException {
      _showError(
        'No results found for the $addressType address: "$address". Please be more specific.',
      );
      return null;
    } on PlatformException catch (e) {
      _showError(
        'Failed to connect to location services. Please check your internet connection. (${e.code})',
      );
      return null;
    } catch (e) {
      _showError(
        'An unexpected error occurred while looking up the $addressType address.',
      );
      return null;
    }
  }

  // validate companion fields (email as unique ID)
  bool _validateCompanions() {
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    final Set<String> usedEmails = {};

    for (int i = 0; i < _companions.length; i++) {
      final c = _companions[i];
      final email = c.emailController.text.trim();
      final ageStr = c.ageController.text.trim();
      final relation = c.relationController.text.trim();

      if (email.isEmpty) {
        _showError('Please enter email for companion ${i + 1}.');
        return false;
      }

      if (!emailRegex.hasMatch(email)) {
        _showError('Please enter a valid email for companion ${i + 1}.');
        return false;
      }

      if (usedEmails.contains(email)) {
        _showError('Duplicate email found for companion ${i + 1}.');
        return false;
      }
      usedEmails.add(email);

      final age = int.tryParse(ageStr);
      if (age == null || age <= 0) {
        _showError('Please enter valid age for companion ${i + 1}.');
        return false;
      }

      if (relation.isEmpty) {
        _showError('Please enter relation for companion ${i + 1}.');
        return false;
      }
    }
    return true;
  }

  Future<void> _handleSubmit(Map<String, dynamic> tripData) async {
    // first validate companions
    if (!_validateCompanions()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final Position? originPosition = tripData['originPosition'];
      final String originPlace = tripData['originPlace'];
      final String destPlace = tripData['destinationPlace'];

      if (originPosition == null && originPlace.isEmpty) {
        throw Exception(
          'Origin is required. Please enter an address or use the live location button.',
        );
      }

      double originLat, originLng;
      if (originPosition != null) {
        originLat = originPosition.latitude;
        originLng = originPosition.longitude;
      } else {
        final originLocation = await _geocodeAddress(originPlace, 'origin');
        if (originLocation == null) return;
        originLat = originLocation.latitude;
        originLng = originLocation.longitude;
      }

      final destLocation = await _geocodeAddress(destPlace, 'destination');
      if (destLocation == null) return;

      double distanceInMeters = Geolocator.distanceBetween(
        originLat,
        originLng,
        destLocation.latitude,
        destLocation.longitude,
      );
      double distanceInKm = distanceInMeters / 1000;

      String mode = tripData['mode'] ?? 'Car';

      // ⭐ use dynamic cost + speed
      double costPerKm = _costPerKm[mode] ?? 10.0;
      double avgSpeed = _avgSpeedKmph[mode] ?? 30.0; // km/h

      // ⭐ estimated time calculation
      double hours = distanceInKm / avgSpeed;
      int estimatedMinutes = (hours * 60).round();

      double perPersonCost = (costPerKm * distanceInKm).roundToDouble();
      double totalCost = (perPersonCost * _numCompanions).roundToDouble();

      double minPerPerson = (perPersonCost * 0.9).roundToDouble();
      double maxPerPerson = (perPersonCost * 1.1).roundToDouble();

      double minTotalCost = (minPerPerson * _numCompanions).roundToDouble();
      double maxTotalCost = (maxPerPerson * _numCompanions).roundToDouble();

      final bool? confirmed = await _showConfirmationDialog(
        distanceInKm,
        perPersonCost,
        totalCost,
        minPerPerson,
        maxPerPerson,
        minTotalCost,
        maxTotalCost,
        _numCompanions,
        mode,
        estimatedMinutes, // ⭐ pass estimated duration
      );

      if (confirmed == true) {
        // build companions list to save
        final companionsList =
        _companions.map((c) => c.toMap()).toList(growable: false);

        final Map<String, dynamic> cleanTripData = {
          'originPlace': tripData['originPlace'],
          'destinationPlace': tripData['destinationPlace'],
          'startTime': tripData['startTime'] != null
              ? Timestamp.fromDate(tripData['startTime'])
              : null,
          'endTime': tripData['endTime'] != null
              ? Timestamp.fromDate(tripData['endTime'])
              : null,
          'mode': tripData['mode'],
          'purpose': tripData['purpose'], // ⭐ from dropdown
          'origin_latitude': originLat,
          'origin_longitude': originLng,
          'destination_latitude': destLocation.latitude,
          'destination_longitude': destLocation.longitude,
          'distance_km': distanceInKm,
          'cost_per_person': perPersonCost,
          'total_cost': totalCost,
          'cost_per_person_range': [minPerPerson, maxPerPerson],
          'total_cost_range': [minTotalCost, maxTotalCost],
          'num_companions': _numCompanions,
          'companions_details': companionsList,
          // ⭐ save estimated duration
          'estimated_duration_minutes': estimatedMinutes,
          'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        };

        await FirebaseFirestore.instance.collection('trips').add(cleanTripData);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Trip saved! Total: ₹${totalCost.toStringAsFixed(0)}',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } on FirebaseException catch (e) {
      _showError('Database Error: ${e.message} (Code: ${e.code})');
    } catch (e) {
      _showError('Failed to save trip: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // format minutes to "X hr Y min" / "X min"
  String _formatDuration(int minutes) {
    if (minutes <= 0) return 'Less than 1 min';
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    if (h == 0) {
      return '$m min';
    } else if (m == 0) {
      return '$h hr';
    } else {
      return '$h hr $m min';
    }
  }

  Future<bool?> _showConfirmationDialog(
      double distance,
      double costOne,
      double totalCost,
      double minCostOne,
      double maxCostOne,
      double minTotalCost,
      double maxTotalCost,
      int numCompanions,
      String mode,
      int estimatedMinutes,
      ) {
    final String timeText = _formatDuration(estimatedMinutes);

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          title: const Text(
            'Trip Summary',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Distance', '${distance.toStringAsFixed(1)} km'),
                const SizedBox(height: 4),
                _buildInfoRow('Mode', mode),
                const SizedBox(height: 4),
                // ⭐ NEW: estimated time row
                _buildInfoRow('Estimated Time', '≈ $timeText'),
                const SizedBox(height: 4),
                _buildInfoRow(
                  'Companions',
                  '$numCompanions person${numCompanions > 1 ? "s" : ""}',
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF0F9FF), Color(0xFFE0F2FE)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF0EA5E9),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.trending_up,
                            color: Colors.blue.shade600,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Estimated Cost Range',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildCostRow(
                        'Per Person',
                        minCostOne,
                        maxCostOne,
                        costOne,
                      ),
                      const SizedBox(height: 12),
                      _buildCostRow(
                        'Total ($numCompanions persons)',
                        minTotalCost,
                        maxTotalCost,
                        totalCost,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF64748B),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'Confirm & Save',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCostRow(
      String label,
      double minCost,
      double maxCost,
      double estimatedCost,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            Text(
              '₹${estimatedCost.toStringAsFixed(0)}',
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '₹${minCost.toStringAsFixed(0)} - ₹${maxCost.toStringAsFixed(0)}',
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Companions Field Widget + dynamic details
  Widget _buildCompanionsField() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Number of Companions',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$_numCompanions person${_numCompanions > 1 ? "s" : ""}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _numCompanions > 1
                          ? () {
                        setState(() {
                          _numCompanions--;
                          _syncCompanionForms();
                        });
                      }
                          : null,
                      icon: Icon(
                        Icons.remove,
                        color: _numCompanions > 1
                            ? const Color(0xFFEF4444)
                            : Colors.grey,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_numCompanions',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _numCompanions < 20
                          ? () {
                        setState(() {
                          _numCompanions++;
                          _syncCompanionForms();
                        });
                      }
                          : null,
                      icon: Icon(
                        Icons.add,
                        color: _numCompanions < 20
                            ? const Color(0xFF22C55E)
                            : Colors.grey,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // companion details forms
          Column(
            children: List.generate(_companions.length, (index) {
              final c = _companions[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Companion ${index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: c.emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'example@gmail.com',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: c.ageController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Age',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GenderField(
                            value: c.gender.isEmpty ? null : c.gender,
                            onChanged: (val) {
                              setState(() {
                                c.gender = val ?? 'Male';
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: c.relationController,
                      decoration: const InputDecoration(
                        labelText: 'Relation (e.g., Friend, Family)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF7F9FC), Color(0xFFEFF6FF)],
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
            'Capture New Trip',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: _isSaving
              ? const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF2563EB),
            ),
          )
              : Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.98),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter Trip Details',
                    style: TextStyle(
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          if (_isLoadingModes)
                            const Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            )
                          else ...[
                            TripFormTabbed(
                              onSubmit: _handleSubmit,
                              availableModes: _availableModes,
                              purposes: _purposes, // ⭐ new
                            ),
                            _buildCompanionsField(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
