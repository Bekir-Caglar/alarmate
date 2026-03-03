import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalAlarmService {
  static const String _storageKey = 'guest_alarms';

  static Future<void> saveAlarm(Map<String, dynamic> alarm) async {
    final prefs = await SharedPreferences.getInstance();
    final alarms = await getAlarms();

    // Generate a unique ID if not present
    if (alarm['id'] == null) {
      alarm['id'] = 'local_${DateTime.now().millisecondsSinceEpoch}';
    }

    alarms.add(alarm);
    await prefs.setString(_storageKey, jsonEncode(alarms));
  }

  static Future<List<Map<String, dynamic>>> getAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_storageKey);
    if (data == null) return [];

    final List<dynamic> list = jsonDecode(data);
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> updateAlarm(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final alarms = await getAlarms();

    final index = alarms.indexWhere((a) => a['id'] == id);
    if (index != -1) {
      alarms[index] = {...alarms[index], ...updates};
      await prefs.setString(_storageKey, jsonEncode(alarms));
    }
  }

  static Future<void> deleteAlarm(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final alarms = await getAlarms();

    alarms.removeWhere((a) => a['id'] == id);
    await prefs.setString(_storageKey, jsonEncode(alarms));
  }
}
