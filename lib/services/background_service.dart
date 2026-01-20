// lib/services/background_location_service.dart
import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BackgroundLocationService {
  /// Call this once in main()
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: "travel_scope_tracker",
      ),
      iosConfiguration: IosConfiguration(
        onForeground: onIosForeground,
        onBackground: onIosBackground,
      ),
    );
  }

  /// Start background tracking service
  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
  }

  /// Stop background tracking service
  static Future<void> stopService() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke("stopService");
    }
  }
}

/// ----------- Background isolate code ---------------
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: "Trip Tracking Active",
      content: "Collecting location in background…",
    );
  }

  service.on("stopService").listen((event) {
    service.stopSelf();
  });

  // Ensure permission
  if (await Geolocator.checkPermission() == LocationPermission.denied) {
    await Geolocator.requestPermission();
  }

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (!(await FlutterBackgroundService().isRunning())) {
      timer.cancel();
      return;
    }

    if (!await Geolocator.isLocationServiceEnabled()) return;

    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      return;
    }

    // Save to Firestore
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection("live_tracking")
        .doc(uid)
        .set({
      "lat": pos.latitude,
      "lng": pos.longitude,
      "timestamp": DateTime.now(),
    }, SetOptions(merge: true));
  });
}

@pragma('vm:entry-point')
void onIosForeground(ServiceInstance service) {}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}
