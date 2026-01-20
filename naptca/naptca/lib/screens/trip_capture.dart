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

class _TripCaptureState extends State<TripCapture> {
  bool _isSaving = false;

  final Map<String, double> _costPerKm = {
    'Car': 15.0,
    'Taxi': 20.0,
    'Motorcycle': 10.0,
    'Bus': 5.0,
    'Train': 3.0,
    'Metro': 4.0,
    'Other': 8.0
  };

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
            'Could not find the $addressType location for: "$address". Please check the address.');
        return null;
      }
      return locations.first;
    } on NoResultFoundException {
      _showError(
          'No results found for the $addressType address: "$address". Please be more specific.');
      return null;
    } on PlatformException catch (e) {
      _showError(
          'Failed to connect to location services. Please check your internet connection. (${e
              .code})');
      return null;
    } catch (e) {
      _showError(
          'An unexpected error occurred while looking up the $addressType address.');
      return null;
    }
  }

  Future<void> _handleSubmit(Map<String, dynamic> tripData) async {
    setState(() {
      _isSaving = true;
    });

    try {
      final Position? originPosition = tripData['originPosition'];
      final String originPlace = tripData['originPlace'];
      final String destPlace = tripData['destinationPlace'];

      if (originPosition == null && originPlace.isEmpty) {
        throw Exception(
            'Origin is required. Please enter an address or use the live location button.');
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
          originLat, originLng, destLocation.latitude, destLocation.longitude);
      double distanceInKm = distanceInMeters / 1000;
      String mode = tripData['mode'] ?? 'Car';
      double cost = (_costPerKm[mode] ?? 10.0) * distanceInKm;

      final bool? confirmed = await _showConfirmationDialog(distanceInKm, cost);

      if (confirmed == true) {
        // Create a clean map with only Firestore-compatible data types.
        final Map<String, dynamic> cleanTripData = {
          'originPlace': tripData['originPlace'],
          'destinationPlace': tripData['destinationPlace'],
          'startTime': tripData['startTime'] != null ? Timestamp.fromDate(
              tripData['startTime']) : null,
          'endTime': tripData['endTime'] != null ? Timestamp.fromDate(
              tripData['endTime']) : null,
          'mode': tripData['mode'],
          'purpose': tripData['purpose'],
          'origin_latitude': originLat,
          'origin_longitude': originLng,
          'destination_latitude': destLocation.latitude,
          'destination_longitude': destLocation.longitude,
          'distance_km': distanceInKm,
          'estimated_cost': cost,
          'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        };

        await FirebaseFirestore.instance.collection('trips').add(cleanTripData);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Trip saved successfully!')));
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

  Future<bool?> _showConfirmationDialog(double distance, double cost) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          title: const Text(
            'Trip Summary',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Distance: ${distance.toStringAsFixed(2)} km',
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Estimated Cost: ₹${cost.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Colors.blue.shade600,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Confirm & Save'),
            ),
          ],
        );
      },
    );
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
                    child: TripFormTabbed(
                      onSubmit: _handleSubmit,
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
