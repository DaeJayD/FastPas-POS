import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'dart:async'; // For TimeoutException

//class GPSValidator {
// Replace with your exact store coordinates (get from Google Maps)
//static const double storeLatitude = 8.502778; // ← 8°30'10.0"N
//static const double storeLongitude = 124.632028; // ← 124°37'55.3"E
//static const double allowedRadius = 15.0; // 15 meters precision
class GPSValidator {
  // Store coordinates in decimal degrees
  static const double storeLatitude = 8.486694444444445; // 8°29'12.1"N
  static const double storeLongitude = 124.65586111111111; // 124°39'21.1"E
  static const double allowedRadius = 15.0; // 15 meters precision

  Future<bool> checkLocationPermission() async {
    final status = await Permission.location.request();
    return status.isGranted;
  }

  Future<bool> isExactlyAtStore() async {
    try {
      // Check and request location permission
      if (!await checkLocationPermission()) {
        throw Exception('Location permission denied');
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      // Get high-precision location
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: Duration(seconds: 15),
      );

      // Validate GPS accuracy
      if (position.accuracy > 20.0) {
        debugPrint('GPS accuracy too low: ${position.accuracy} meters');
        return false;
      }

      // Calculate distance to store
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        storeLatitude,
        storeLongitude,
      );

      debugPrint('=== GPS Validation ===');
      debugPrint('Distance from store: ${distance.toStringAsFixed(2)} meters');
      debugPrint(
        'GPS accuracy: ${position.accuracy.toStringAsFixed(2)} meters',
      );
      debugPrint('Required accuracy: < 20.0 meters');
      debugPrint('Allowed radius: $allowedRadius meters');
      debugPrint('Validation result: ${distance <= allowedRadius}');
      debugPrint('=====================');

      return distance <= allowedRadius;
    } on TimeoutException catch (e) {
      debugPrint('GPS timeout: $e');
      return false;
    } catch (e) {
      debugPrint('GPS validation error: $e');
      return false;
    }
  }

  // Method to get precise coordinates (use this once to set your store location)
  Future<void> getCurrentPreciseLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      debugPrint('=== YOUR STORE COORDINATES ===');
      debugPrint('Latitude: ${position.latitude}');
      debugPrint('Longitude: ${position.longitude}');
      debugPrint('=============================');
    } catch (e) {
      debugPrint('Error getting coordinates: $e');
    }
  }
}
