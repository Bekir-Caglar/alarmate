import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../database/local_db.dart';
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

  static int calculateLocalId(String timeStr, String ampm) {
    // String.hashCode is NOT stable across app restarts/runs in Dart/Flutter.
    // We implement a simple stable rolling hash for HH:mmAM/PM strings.
    final s = (timeStr.trim() + ampm.trim()).toUpperCase();
    int hash = 0;
    for (int i = 0; i < s.length; i++) {
      hash = (31 * hash + s.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    // Return a 31-bit positive integer for hardware alarm ID compatibility.
    return hash;
  }

  static Future<void> syncAlarmsWithDevice({int? dismissedAlarmId}) async {
    final user = FirebaseAuth.instance.currentUser;
    final bool isGuest = user == null || user.isAnonymous;

    List<Map<String, dynamic>> alarmsList = [];

    if (isGuest) {
      // Hem Firebase Anonim hem de "Misafir Mod" (Offline Guest) için yerel DB kullanıyoruz.
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
              data['id'] = id.toString();
              alarmsList.add(data);
            }
          }
        }
      } catch (e) {
        // Online değilse veya hata aldıysa yerel cache'i kullan
        alarmsList = await LocalDb.instance.getAll('alarms');
      }
    }

    // Get IDs of alarms that SHOULD be on the device
    final List<int> activeIds = [];
    for (var alarm in alarmsList) {
      final timeStr = alarm['time'] as String;
      final ampm = alarm['ampm'] as String;
      final int localId = calculateLocalId(timeStr, ampm);

      // Handle one-time alarm deactivation
      if (dismissedAlarmId != null && localId == dismissedAlarmId) {
        final days = (alarm['days'] as List?) ?? [];
        if (days.isEmpty && alarm['isActive'] == true) {
          debugPrint('Deactivating one-time alarm: ${alarm['id']}');

          // Yerel veritabanında kapat
          await LocalAlarmService.updateAlarm(alarm['id'], {'isActive': false});

          // Eğer Firebase kullanıcısı (Anonim olmayan) ise bulutta da kapat
          if (user != null && !user.isAnonymous) {
            await FirebaseDatabase.instance
                .ref()
                .child('alarms')
                .child(alarm['id'])
                .child('isActive')
                .set(false);
          }

          alarm['isActive'] =
              false; // Bu senkronizasyon döngüsü için yerel kopyayı güncelle
        }
      }

      if (alarm['isActive'] == true) {
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
        final int localId = calculateLocalId(timeStr, ampm);

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

    final timeStrClean = timeStr.trim();
    final ampmClean = ampm.trim();

    DateTime now = DateTime.now();
    DateTime alarmTime;

    if (days.isEmpty) {
      alarmTime = DateTime(now.year, now.month, now.day, hour, min);

      // If the scheduled time is in the past (even by seconds),
      // check if it's the same minute as now.
      if (alarmTime.isBefore(now)) {
        if (alarmTime.hour == now.hour && alarmTime.minute == now.minute) {
          // It's the current minute. Schedule for 5 seconds from now to be safe.
          alarmTime = now.add(const Duration(seconds: 5));
        } else {
          // It's definitely in the past, move to tomorrow.
          alarmTime = alarmTime.add(const Duration(days: 1));
        }
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

    final int localId = calculateLocalId(timeStrClean, ampmClean);

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
