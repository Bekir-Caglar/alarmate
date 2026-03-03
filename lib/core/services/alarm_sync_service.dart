import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'local_alarm_service.dart';

class AlarmSyncService {
  static Future<void> toggleAllAlarms(bool active) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (user.isAnonymous) {
      final alarms = await LocalAlarmService.getAlarms();
      for (var alarm in alarms) {
        await LocalAlarmService.updateAlarm(alarm['id'], {'isActive': active});
      }
    } else {
      try {
        final db = FirebaseDatabase.instance.ref();
        final memberships = await db
            .child('memberships')
            .child(user.uid)
            .get()
            .timeout(const Duration(seconds: 3));

        if (memberships.exists && memberships.value is Map) {
          final alarmIds = (memberships.value as Map).keys;
          final updates = <String, dynamic>{};
          for (var id in alarmIds) {
            updates['alarms/$id/isActive'] = active;
          }
          await db.update(updates).timeout(const Duration(seconds: 3));
        }
      } catch (e) {
        // Timeout or Network Error (Offline mode) -> Edit Local Alarms Instead to prevent freeze
        final alarms = await LocalAlarmService.getAlarms();
        for (var alarm in alarms) {
          await LocalAlarmService.updateAlarm(alarm['id'], {
            'isActive': active,
          });
        }
      }
    }
  }

  static Future<void> syncAlarmsWithDevice() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await Alarm.stopAll();
      return;
    }

    List<Map<String, dynamic>> alarmsList = [];

    if (user.isAnonymous) {
      alarmsList = await LocalAlarmService.getAlarms();
    } else {
      try {
        final db = FirebaseDatabase.instance.ref();
        final memberships = await db
            .child('memberships')
            .child(user.uid)
            .get()
            .timeout(const Duration(seconds: 3));

        if (memberships.exists && memberships.value is Map) {
          final alarmIds = (memberships.value as Map).keys;
          for (var id in alarmIds) {
            final alarmSnap = await db
                .child('alarms')
                .child(id)
                .get()
                .timeout(const Duration(seconds: 3));
            if (alarmSnap.exists) {
              final data = Map<String, dynamic>.from(alarmSnap.value as Map);
              data['id'] = id;
              alarmsList.add(data);
            }
          }
        }
      } catch (e) {
        // If offline, use local database alarms for device sync
        alarmsList = await LocalAlarmService.getAlarms();
      }
    }

    // Get IDs of alarms that SHOULD be on the device
    final List<int> activeIds = [];
    for (var alarm in alarmsList) {
      if (alarm['isActive'] == true) {
        final timeStr = alarm['time'] as String;
        final ampm = alarm['ampm'] as String;
        final int localId = timeStr.hashCode.abs() ^ ampm.hashCode;
        activeIds.add(localId);
      }
    }

    // Stop only orphaned or deleted alarms, BUT skip the one currently ringing
    final existingAlarms = await Alarm.getAlarms();
    for (var existing in existingAlarms) {
      // If the alarm is ringing, we ABSOLUTELY DO NOT stop it here.
      // Navigator/MissionScreen will handle stopping it later.
      final bool isRinging = await Alarm.isRinging(existing.id);
      if (isRinging) continue;

      if (!activeIds.contains(existing.id)) {
        await Alarm.stop(existing.id);
      }
    }

    // Schedule / Update alarms (Alarm.set handles replacement if ID matches)
    for (var alarm in alarmsList) {
      if (alarm['isActive'] == true) {
        final timeStr = alarm['time'] as String;
        final ampm = alarm['ampm'] as String;
        final int localId = timeStr.hashCode.abs() ^ ampm.hashCode;

        // CRITICAL: If this alarm is ALREADY ringing, DON'T call Alarm.set again!
        // Calling Alarm.set on a ringing alarm stops the audio for that alarm.
        final bool isRinging = await Alarm.isRinging(localId);
        if (isRinging) {
          debugPrint('Skipping reschedule for ringing alarm: $localId');
          continue;
        }

        await _scheduleAlarm(alarm);
      }
    }
  }

  static Future<void> _scheduleAlarm(Map<String, dynamic> alarm) async {
    final timeStr = alarm['time'] as String; // "08:30"
    final ampm = alarm['ampm'] as String; // "AM"
    final parts = timeStr.split(':');
    int hour = int.parse(parts[0]);
    final min = int.parse(parts[1]);

    if (ampm == 'PM' && hour < 12) hour += 12;
    if (ampm == 'AM' && hour == 12) hour = 0;

    final days =
        (alarm['days'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [];

    DateTime now = DateTime.now();
    DateTime alarmTime;

    if (days.isEmpty) {
      alarmTime = DateTime(now.year, now.month, now.day, hour, min);
      if (alarmTime.isBefore(now)) {
        alarmTime = alarmTime.add(const Duration(days: 1));
      }
    } else {
      // Find the next occurrence among selected days
      DateTime candidate = DateTime(now.year, now.month, now.day, hour, min);

      // If today is selected AND the time hasn't passed, use today.
      // Otherwise, look for the next selected day.
      if (candidate.isAfter(now) && days.contains(candidate.weekday)) {
        alarmTime = candidate;
      } else {
        // Look ahead for the next 7 days
        DateTime found = candidate;
        for (int i = 1; i <= 7; i++) {
          DateTime next = candidate.add(Duration(days: i));
          if (days.contains(next.weekday)) {
            found = next;
            break;
          }
        }
        alarmTime = found;
      }
    }

    final int localId = timeStr.hashCode.abs() ^ ampm.hashCode;

    final alarmSettings = AlarmSettings(
      id: localId,
      dateTime: alarmTime,
      assetAudioPath: 'assets/alarm.mp3',
      loopAudio: true,
      vibrate: true,
      volumeSettings: VolumeSettings.fade(
        fadeDuration: const Duration(seconds: 3),
        volume: 1.0,
      ),
      notificationSettings: NotificationSettings(
        title: (alarm['groupName'] ?? 'ALARM').toString().toUpperCase(),
        body: 'UYANMA VAKTİ! ${alarm['mission'] ?? 'GÖREV'} GÖREVİNİ TAMAMLA!',
      ),
      androidFullScreenIntent: true,
      androidStopAlarmOnTermination: false,
      warningNotificationOnKill: Platform.isIOS,
    );

    // Save mission/difficulty to prefs for MissionScreen to read
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'alarm_${localId}_mission',
      alarm['mission'] ?? 'BİLİNMİYOR',
    );
    await prefs.setString(
      'alarm_${localId}_difficulty',
      alarm['difficulty'] ?? 'ORTA',
    );

    await Alarm.set(alarmSettings: alarmSettings);
  }

  /// Kullanıcı bir alarm güncellemesini onayladığında çağrılır.
  /// pendingUpdates node'unu temizler ve cihaz alarmlarını günceller.
  static Future<void> confirmUpdate(String alarmId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final db = FirebaseDatabase.instance.ref();
    await db.child('pendingUpdates').child(user.uid).child(alarmId).remove();

    // Cihaz alarmlarını güncelle
    await syncAlarmsWithDevice();
  }

  /// Kullanıcının tüm bekleyen güncellemelerini temizler.
  static Future<void> clearAllPendingUpdates() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final db = FirebaseDatabase.instance.ref();
    await db.child('pendingUpdates').child(user.uid).remove();
  }
}
