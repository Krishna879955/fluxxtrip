class Trip {
  final int tripNumber;
  final String originPlace;
  final DateTime startTime;
  final String destinationPlace;
  final DateTime endTime;
  final String mode;
  final double distance;
  final String purpose;
  final int companions;
  final int frequency;
  final double cost;

  Trip({
    required this.tripNumber,
    required this.originPlace,
    required this.startTime,
    required this.destinationPlace,
    required this.endTime,
    required this.mode,
    required this.distance,
    required this.purpose,
    required this.companions,
    required this.frequency,
    required this.cost,
  });

  Map<String, dynamic> toJson() => {
    'tripNumber': tripNumber,
    'origin': originPlace,
    'startTime': startTime.toIso8601String(),
    'destination': destinationPlace,
    'endTime': endTime.toIso8601String(),
    'mode': mode,
    'distance': distance,
    'purpose': purpose,
    'companions': companions,
    'frequency': frequency,
    'cost': cost,
  };

  static Trip fromJson(Map<String, dynamic> json) => Trip(
    tripNumber: json['tripNumber'],
    originPlace: json['origin'],
    startTime: DateTime.parse(json['startTime']),
    destinationPlace: json['destination'],
    endTime: DateTime.parse(json['endTime']),
    mode: json['mode'],
    distance: (json['distance'] as num).toDouble(),
    purpose: json['purpose'],
    companions: json['companions'],
    frequency: json['frequency'],
    cost: (json['cost'] as num).toDouble(),
  );
}
