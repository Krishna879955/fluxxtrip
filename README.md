# TravelScope (naptca)

**TravelScope** is a comprehensive Flutter application designed for travel tracking, transit management, and trip history analysis. It leverages Firebase for backend services and Google Maps for real-time location features.

## 🚀 Features

*   **Role-Based Access Control:** Secure authentication with distinct dashboards for **Users** and **Admins**.
*   **User Dashboard:** Access to trip history, live tracking, and smart transit features.
*   **Admin Dashboard:** Manage users, view system-wide trips, and oversee transit operations.
*   **Real-Time Tracking:** Live location tracking using **Google Maps**.
*   **Trip Management:**
    *   **Trip Capture:** Record new trips with start/end locations.
    *   **Trip History:** View past trips with detailed statistics.
    *   **End-to-End Navigation:** Complete trip planning and navigation assistance.
*   **Smart Transit:** Live updates and monitoring for transit systems.
*   **Data Visualization:** Visual analytics of travel data using charts.

## 🛠️ Tech Stack

*   **Frontend:** [Flutter](https://flutter.dev/) (Dart)
*   **Backend:** [Firebase](https://firebase.google.com/)
    *   **Authentication:** specialized login/registration flows.
    *   **Cloud Firestore:** Real-time database for user profiles, roles, and trip data.
    *   **Firebase Storage:** (Configured for potential media assets).
*   **Maps & Location:**
    *   `google_maps_flutter`: Map rendering and interaction.
    *   `geolocator`: Current device location.
    *   `geocoding`: Address to coordinate conversion.
    *   `flutter_polyline_points`: Route visualization.
*   **State Management:** `provider`
*   **Background Services:** `flutter_background_service` for persistent tracking.

## 📂 Project Structure

The project follows a standard Flutter architecture:

```
lib/
├── assets/          # Static assets (icons, images)
├── screens/         # UI Screens (Pages)
│   ├── login.dart
│   ├── registration.dart
│   ├── user_dashboard.dart
│   ├── admin_dashboard.dart
│   ├── trip_capture.dart
│   ├── trip_history.dart
│   ├── live_tracking_page.dart
│   ├── smart_transit_live_page.dart
│   ├── end_to_end.dart
│   └── trips_list_page.dart
├── main.dart        # Application entry point & Routing
└── firebase_options.dart # Firebase configuration (generated)
```

## 🏁 Getting Started

### Prerequisites

*   [Flutter SDK](https://docs.flutter.dev/get-started/install) (Version 3.3.0 or higher)
*   Dart SDK
*   A Firebase Project
*   Google Maps API Key

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-username/naptca.git
    cd naptca
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Configure Firebase:**
    *   Install the Firebase CLI.
    *   Run `flutterfire configure` to generate `firebase_options.dart`.

4.  **Configure Google Maps:**
    *   Get an API Key from the Google Cloud Console.
    *   Add the key to your `android/app/src/main/AndroidManifest.xml` and `ios/Runner/AppDelegate.swift`.

5.  **Run the App:**
    ```bash
    flutter run
    ```

## 🤝 Contributing

Contributions are welcome! Please fork the repository and submit a pull request for any enhancements or bug fixes.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
