import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/local_db.dart';

class LocalAlarmService {
  static const String _storageKey = 'guest_alarms';

  /// Sadece misafir mod veya eski alarmları migrate et
  static Future<void> migrateOldAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_storageKey);
    if (data != null) {
      final List<dynamic> list = jsonDecode(data);
      for (var e in list) {
        final alarm = Map<String, dynamic>.from(e);
        await LocalDb.instance.save('alarms', alarm['id'], alarm);
      }
      await prefs.remove(_storageKey);
    }
  }

  static Future<void> saveAlarm(Map<String, dynamic> alarm) async {
    if (alarm['id'] == null) {
      alarm['id'] = 'local_${DateTime.now().millisecondsSinceEpoch}';
    }
    await LocalDb.instance.save('alarms', alarm['id'], alarm);
  }

  static Future<List<Map<String, dynamic>>> getAlarms() async {
    await migrateOldAlarms();
    final all = await LocalDb.instance.getAll('alarms');
    return all.where((e) => (e['id'] as String).startsWith('local_')).toList();
  }

  static Future<void> updateAlarm(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final old = await LocalDb.instance.getById('alarms', id);
    if (old != null) {
      final updated = {...old, ...updates};
      await LocalDb.instance.save('alarms', id, updated);
    }
  }

  static Future<void> deleteAlarm(String id) async {
    await LocalDb.instance.delete('alarms', id);
  }
}
