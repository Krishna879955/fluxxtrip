// api_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/trip.dart';

class ApiService {
  static final _tripsRef = FirebaseFirestore.instance.collection('trips');

  /// POST /trips  – save one trip from the app
  static Future<bool> saveTrip(Trip trip) async {
    await _tripsRef.add(trip.toJson());
    return true;
  }

  /// GET /trips?startDate=&endDate=&mode=
  static Future<List<Trip>> getTrips({
    DateTime? startDate,
    DateTime? endDate,
    String? mode,
  }) async {
    Query<Map<String, dynamic>> query = _tripsRef;

    if (startDate != null) {
      query = query.where(
        'startTime',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
      );
    }
    if (endDate != null) {
      query = query.where(
        'startTime',
        isLessThanOrEqualTo: Timestamp.fromDate(endDate),
      );
    }
    if (mode != null && mode != 'All') {
      query = query.where('mode', isEqualTo: mode);
    }

    final snap = await query.orderBy('startTime').get();
    return snap.docs
        .map((doc) => Trip.fromJson(doc.data()))
        .toList();
  }

  /// GET /export  – raw docs for CSV / JSON export
  static Future<QuerySnapshot<Map<String, dynamic>>> exportTripsRaw({
    DateTime? startDate,
    DateTime? endDate,
    String? mode,
  }) async {
    Query<Map<String, dynamic>> query = _tripsRef;

    if (startDate != null) {
      query = query.where(
        'startTime',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
      );
    }
    if (endDate != null) {
      query = query.where(
        'startTime',
        isLessThanOrEqualTo: Timestamp.fromDate(endDate),
      );
    }
    if (mode != null && mode != 'All') {
      query = query.where('mode', isEqualTo: mode);
    }

    return query.orderBy('startTime').get();
  }
}