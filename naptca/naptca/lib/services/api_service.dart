// api_service.dart

import '../models/trip.dart';

class ApiService {
  // Local in-memory storage for trips
  static final List<Trip> _trips = [];

  // Store trip data locally instead of sending to a backend
  static Future<bool> saveTrip(Trip trip) async {
    _trips.add(trip);
    await Future.delayed(Duration(milliseconds: 300)); // Simulate saving delay
    return true;
  }

  static Future<List<Trip>> getTrips() async {
    return _trips;
  }
}
