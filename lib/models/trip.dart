class CompanionInfo {
  final String name;
  final int age;
  final String gender;
  final String relation;

  CompanionInfo({
    required this.name,
    required this.age,
    required this.gender,
    required this.relation,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'age': age,
    'gender': gender,
    'relation': relation,
  };

  factory CompanionInfo.fromJson(Map<String, dynamic> json) {
    return CompanionInfo(
      name: json['name'] ?? '',
      age: (json['age'] ?? 0) is int
          ? (json['age'] ?? 0)
          : int.tryParse(json['age'].toString()) ?? 0,
      gender: json['gender'] ?? '',
      relation: json['relation'] ?? '',
    );
  }
}

class Trip {
  final int tripNumber;
  final String originPlace;
  final DateTime startTime;
  final String destinationPlace;
  final DateTime endTime;
  final String mode;
  final double distance;
  final String purpose;
  final int companions; // total count
  final int frequency;
  final double cost;

  // NEW: detailed list of companions
  final List<CompanionInfo> companionsDetails;

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
    this.companionsDetails = const [],
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
    // NEW: save companions list if you want to store with this model
    'companions_details':
    companionsDetails.map((c) => c.toJson()).toList(),
  };

  static Trip fromJson(Map<String, dynamic> json) {
    final rawList = json['companions_details'];
    final List<CompanionInfo> companionsDetails;
    if (rawList is List) {
      companionsDetails = rawList
          .whereType<Map<String, dynamic>>()
          .map((m) => CompanionInfo.fromJson(m))
          .toList();
    } else {
      companionsDetails = const [];
    }

    return Trip(
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
      companionsDetails: companionsDetails,
    );
  }
}
