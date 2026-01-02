import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import '../config/api_config.dart';

class LocationService {
  static const String _locationEnabledKey = 'location_enabled';
  static const String _lastLocationUpdateKey = 'last_location_update';

  /// Check if location services are enabled on the device
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check current permission status
  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Request location permission
  Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  /// Get user's current location with permission handling
  Future<Map<String, dynamic>?> getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) {
          print('Location services are disabled.');
        }
        return null;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (kDebugMode) {
            print('Location permissions are denied');
          }
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) {
          print('Location permissions are permanently denied');
        }
        return null;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 100,
        ),
      );

      // Reverse geocode to get address
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isEmpty) {
        return null;
      }

      Placemark place = placemarks[0];

      final locationData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'country': place.country ?? '',
        'countryCode': place.isoCountryCode ?? '',
        'city': place.locality ?? place.subAdministrativeArea ?? '',
        'state': place.administrativeArea ?? '',
        'timestamp': DateTime.now().toIso8601String(),
      };

      if (kDebugMode) {
        print('Location obtained: ${locationData['city']}, ${locationData['country']}');
      }

      return locationData;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting location: $e');
      }
      return null;
    }
  }

  /// Update user's location on the backend
  Future<bool> updateLocationOnBackend() async {
    try {
      final locationData = await getCurrentLocation();
      if (locationData == null) {
        return false;
      }

      final token = await AuthService.getToken();
      if (token == null) {
        if (kDebugMode) {
          print('No auth token available');
        }
        return false;
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth/update-location'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'latitude': locationData['latitude'],
          'longitude': locationData['longitude'],
          'country': locationData['country'],
          'countryCode': locationData['countryCode'],
          'city': locationData['city'],
          'state': locationData['state'],
        }),
      );

      if (response.statusCode == 200) {
        // Save location enabled status
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_locationEnabledKey, true);
        await prefs.setString(_lastLocationUpdateKey, DateTime.now().toIso8601String());

        if (kDebugMode) {
          print('Location updated on backend successfully');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('Failed to update location on backend: ${response.statusCode}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating location on backend: $e');
      }
      return false;
    }
  }

  /// Check if user has enabled location
  Future<bool> isLocationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_locationEnabledKey) ?? false;
  }

  /// Disable location tracking
  Future<void> disableLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_locationEnabledKey, false);
  }

  /// Check if location needs updating (update every 24 hours)
  Future<bool> shouldUpdateLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUpdateStr = prefs.getString(_lastLocationUpdateKey);

    if (lastUpdateStr == null) {
      return true;
    }

    final lastUpdate = DateTime.parse(lastUpdateStr);
    final hoursSinceUpdate = DateTime.now().difference(lastUpdate).inHours;

    // Update if more than 24 hours have passed
    return hoursSinceUpdate >= 24;
  }

  /// Request location permission and update on backend
  Future<bool> enableLocationAndUpdate() async {
    try {
      final permission = await requestPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      return await updateLocationOnBackend();
    } catch (e) {
      if (kDebugMode) {
        print('Error enabling location: $e');
      }
      return false;
    }
  }
}
