import 'package:http/http.dart' as http;
import 'dart:convert';

class DirectionsService {
  static Future<Map<String, dynamic>?> fetchDirections({
    required String origin,
    required String destination,
    required String apiKey,
    String mode = 'driving',
  }) async {
    final encodedOrigin = Uri.encodeComponent(origin);
    final encodedDest = Uri.encodeComponent(destination);
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?origin=$encodedOrigin&destination=$encodedDest&mode=$mode&key=$apiKey'
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'OK') return data;
    }
    return null;
  }
}
