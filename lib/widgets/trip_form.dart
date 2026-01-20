import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';

class TripFormTabbed extends StatefulWidget {
  final Function(Map<String, dynamic>) onSubmit;
  final List<String> availableModes;
  final List<String> purposes; // ⭐ purposes from parent

  const TripFormTabbed({
    Key? key,
    required this.onSubmit,
    required this.availableModes,
    required this.purposes,
  }) : super(key: key);

  @override
  State<TripFormTabbed> createState() => _TripFormTabbedState();
}

class _TripFormTabbedState extends State<TripFormTabbed> {
  final _formKey = GlobalKey<FormState>();
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();

  DateTime? _startTime;
  DateTime? _endTime;
  String? _selectedMode;
  String? _selectedPurpose;
  Position? _originPosition; // store origin coordinates

  @override
  void initState() {
    super.initState();

    // ⭐ default mode & purpose if lists not empty
    if (widget.availableModes.isNotEmpty) {
      _selectedMode = widget.availableModes.first;
    }
    if (widget.purposes.isNotEmpty) {
      _selectedPurpose = widget.purposes.first;
    }
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _getLiveLocationForOrigin() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      _originPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        _originPosition!.latitude,
        _originPosition!.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        _originController.text =
        '${place.name}, ${place.locality}, ${place.postalCode}, ${place.country}';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get location: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      widget.onSubmit({
        'originPlace': _originController.text.trim(),
        'destinationPlace': _destinationController.text.trim(),
        'startTime': _startTime,
        'endTime': _endTime,
        'mode': _selectedMode,
        'purpose': _selectedPurpose, // ⭐ send selected purpose
        'originPosition': _originPosition,
      });
    }
  }

  Future<void> _pickDateTime(BuildContext context, bool isStart) async {
    DateTime initialDate =
    isStart ? DateTime.now() : (_startTime ?? DateTime.now());

    DateTime? date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (date == null) return;

    TimeOfDay initialTime = TimeOfDay.now();
    TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (time == null) return;

    final dt =
    DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startTime = dt;
      } else {
        _endTime = dt;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final modes = widget.availableModes;
    final purposes = widget.purposes;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextFormField(
              controller: _originController,
              decoration:
              _inputDecoration('Origin', Icons.location_on).copyWith(
                suffixIcon: IconButton(
                  icon: const Icon(
                    Icons.my_location_rounded,
                    color: Color(0xFF2563EB),
                  ),
                  onPressed: _getLiveLocationForOrigin,
                  tooltip: 'Use current location',
                ),
              ),
              style: const TextStyle(color: Color(0xFF111827)),
              validator: (value) =>
              value == null || value.isEmpty ? 'Please enter an origin' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _destinationController,
              decoration:
              _inputDecoration('Destination', Icons.flag_rounded),
              style: const TextStyle(color: Color(0xFF111827)),
              validator: (value) => value == null || value.isEmpty
                  ? 'Please enter a destination'
                  : null,
            ),
            const SizedBox(height: 16),
            _buildDateTimePicker(
              'Start Time',
              _startTime,
                  () => _pickDateTime(context, true),
            ),
            const SizedBox(height: 16),
            _buildDateTimePicker(
              'End Time',
              _endTime,
                  () => _pickDateTime(context, false),
            ),
            const SizedBox(height: 16),

            // ⭐ Dynamic modes dropdown
            DropdownButtonFormField<String>(
              decoration:
              _inputDecoration('Mode of Transport', Icons.commute),
              value: _selectedMode,
              dropdownColor: Colors.white,
              style: const TextStyle(color: Color(0xFF111827)),
              items: modes.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedMode = newValue;
                });
              },
              validator: (value) {
                if (modes.isEmpty) {
                  return 'No transport modes available. Please contact admin.';
                }
                return value == null ? 'Please select a mode' : null;
              },
            ),

            const SizedBox(height: 16),

            // ⭐ Purpose dropdown
            DropdownButtonFormField<String>(
              decoration: _inputDecoration(
                'Purpose of Trip',
                Icons.help_outline_rounded,
              ),
              value: _selectedPurpose,
              dropdownColor: Colors.white,
              style: const TextStyle(color: Color(0xFF111827)),
              items: purposes.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedPurpose = newValue;
                });
              },
              validator: (value) {
                if (purposes.isEmpty) {
                  return 'No purposes available. Please contact admin.';
                }
                return value == null ? 'Please select a purpose' : null;
              },
            ),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 1.5,
              ),
              child: const Text(
                'Save Trip',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimePicker(
      String label,
      DateTime? dateTime,
      VoidCallback onPressed,
      ) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: _inputDecoration(label, Icons.calendar_today_rounded),
        child: Text(
          dateTime != null
              ? DateFormat.yMd().add_jm().format(dateTime)
              : 'Select Date & Time',
          style: TextStyle(
            color: dateTime != null
                ? const Color(0xFF111827)
                : const Color(0xFF9CA3AF),
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Color(0xFF6B7280),
        fontSize: 13,
      ),
      prefixIcon: Icon(
        icon,
        color: const Color(0xFF94A3B8),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
      const EdgeInsets.symmetric(vertical: 14, horizontal: 0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFFE5E7EB),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFF2563EB),
          width: 1.6,
        ),
      ),
    );
  }
}
