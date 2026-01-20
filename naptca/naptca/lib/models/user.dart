class User {
  final String id;
  final String email;
  final bool isAdmin;

  User({
    required this.id,
    required this.email,
    required this.isAdmin,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      isAdmin: map['isAdmin'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'isAdmin': isAdmin,
    };
  }
}
