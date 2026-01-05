import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';

class StatusViewService {
  static const String _boxName = 'viewedStatuses';
  static Box? _box;

  // Initialize the box
  static Future<void> init() async {
    try {
      _box = await Hive.openBox(_boxName);
      if (kDebugMode) {
        print('✅ StatusViewService initialized');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing StatusViewService: $e');
      }
    }
  }

  // Mark a status as viewed
  static Future<void> markAsViewed(String statusId) async {
    if (_box == null) await init();
    if (_box == null) return;

    try {
      await _box!.put(statusId, DateTime.now().toIso8601String());
      if (kDebugMode) {
        print('👁️  Marked status as viewed: $statusId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error marking status as viewed: $e');
      }
    }
  }

  // Check if a status has been viewed
  static bool hasViewed(String statusId) {
    if (_box == null) return false;
    return _box!.containsKey(statusId);
  }

  // Get all viewed status IDs
  static List<String> getViewedStatusIds() {
    if (_box == null) return [];
    return _box!.keys.cast<String>().toList();
  }

  // Clear old viewed statuses (older than 24 hours)
  static Future<void> clearOldViews() async {
    if (_box == null) await init();
    if (_box == null) return;

    try {
      final now = DateTime.now();
      final keysToDelete = <String>[];

      for (var key in _box!.keys) {
        final viewedAtString = _box!.get(key);
        if (viewedAtString != null) {
          try {
            final viewedAt = DateTime.parse(viewedAtString);
            final difference = now.difference(viewedAt);

            // If viewed more than 24 hours ago, mark for deletion
            if (difference.inHours >= 24) {
              keysToDelete.add(key);
            }
          } catch (e) {
            // If can't parse date, delete it
            keysToDelete.add(key);
          }
        }
      }

      // Delete old views
      for (var key in keysToDelete) {
        await _box!.delete(key);
      }

      if (kDebugMode && keysToDelete.isNotEmpty) {
        print('🗑️  Cleared ${keysToDelete.length} old status views');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error clearing old views: $e');
      }
    }
  }

  // Clear all viewed statuses
  static Future<void> clearAll() async {
    if (_box == null) await init();
    if (_box == null) return;

    try {
      await _box!.clear();
      if (kDebugMode) {
        print('🗑️  Cleared all viewed statuses');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error clearing all views: $e');
      }
    }
  }
}
