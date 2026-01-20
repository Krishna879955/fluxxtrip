class AuthService {
  // Simulated user data for demonstration
  static bool isLoggedIn = false;
  static bool isAdmin = false;
  static String userEmail = '';

  static Future<bool> login(String email, String password, bool admin) async {
    // TODO: Replace with real authentication logic
    await Future.delayed(Duration(seconds: 1));
    isLoggedIn = true;
    isAdmin = admin;
    userEmail = email;
    return true; // success
  }

  static Future<bool> register(String email, String password, bool admin) async {
    // TODO: Replace with real registration logic
    await Future.delayed(Duration(seconds: 1));
    return true; // success
  }

  static void logout() {
    isLoggedIn = false;
    isAdmin = false;
    userEmail = '';
  }
}
