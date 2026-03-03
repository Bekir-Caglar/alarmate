import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../core/database/local_db.dart';
import 'package:flutter/foundation.dart';

class DataRepository {
  static final DataRepository instance = DataRepository._init();
  DataRepository._init();

  final _db = FirebaseDatabase.instance.ref();
  final _localDb = LocalDb.instance;

  StreamSubscription? _membershipsSub;
  StreamSubscription? _invitationsSub;
  StreamSubscription? _currentUserSub;
  final Map<String, StreamSubscription> _alarmSubs = {};

  void startFirebaseSync() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      // Offline/Misafir modu ise Firebase sync çalıştırma
      return;
    }

    // İlk dinleyicileri başlat (Firebase onValue anında ilk datayı da çeker)
    _startListeners(user.uid);
  }

  Future<void> forceSync() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    try {
      // Refresh Indicator vb. mekanizmalar için manuel tetikleme
      final snap = await _db
          .child('memberships')
          .child(user.uid)
          .get()
          .timeout(const Duration(seconds: 5));
      if (snap.exists && snap.value is Map) {
        final alarmIds = Map<String, dynamic>.from(
          snap.value as Map,
        ).keys.toList();
        await _syncAlarms(alarmIds);
      }

      final invSnap = await _db
          .child('invitations')
          .child(user.uid)
          .get()
          .timeout(const Duration(seconds: 5));
      if (invSnap.exists && invSnap.value is Map) {
        final data = Map<String, dynamic>.from(invSnap.value as Map);
        await _localDb.saveAll(
          'invitations',
          data.cast<String, Map<String, dynamic>>(),
        );
      }

      final userSnap = await _db
          .child('users')
          .child(user.uid)
          .get()
          .timeout(const Duration(seconds: 5));
      if (userSnap.exists && userSnap.value is Map) {
        final data = Map<String, dynamic>.from(userSnap.value as Map);
        await _localDb.save('users', user.uid, data);
      }
    } catch (e) {
      debugPrint('Force sync failed: $e');
    }
  }

  void _startListeners(String uid) {
    // 0. Sync Current User Profile
    _currentUserSub?.cancel();
    _currentUserSub = _db.child('users').child(uid).onValue.listen((
      event,
    ) async {
      if (event.snapshot.exists && event.snapshot.value is Map) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        await _localDb.save('users', uid, data);
      }
    });

    // 1. Sync Memberships -> Alarms
    _membershipsSub?.cancel();
    _membershipsSub = _db.child('memberships').child(uid).onValue.listen((
      event,
    ) async {
      if (event.snapshot.exists && event.snapshot.value is Map) {
        final alarmIds = Map<String, dynamic>.from(
          event.snapshot.value as Map,
        ).keys.toList();

        // Her değiştiğinde LocalDb'yi senkronize et
        await _syncAlarms(alarmIds);
        _updateAlarmListeners(alarmIds);
      } else {
        // Sadece cloud'dan gelenleri sil, local olanlara (misafir mod) dokunma
        final alarms = await _localDb.getAll('alarms');
        final toDelete = alarms
            .map((e) => e['id'] as String)
            .where((id) => !id.startsWith('local_'))
            .toList();
        if (toDelete.isNotEmpty) {
          await _localDb.deleteMany('alarms', toDelete);
        }
        _removeAllAlarmListeners();
      }
    });

    // 2. Sync Invitations -> Local Invitations
    _invitationsSub?.cancel();
    _invitationsSub = _db.child('invitations').child(uid).onValue.listen((
      event,
    ) async {
      if (event.snapshot.exists && event.snapshot.value is Map) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);

        // Data map şeklindedir: { alarmId: { groupName: ... } }
        // Hepsini birden LocalDb'ye atıyoruz, LocalDb stream atarak anında UI günceller.
        await _localDb.saveAll(
          'invitations',
          data.cast<String, Map<String, dynamic>>(),
        );

        // Eğer sunucuda silinen davetler varsa, yerelden de silelim
        final localInvs = await _localDb.getAll('invitations');
        final localIds = localInvs.map((e) => e['id'] as String).toList();
        final toDelete = localIds.where((id) => !data.containsKey(id)).toList();
        if (toDelete.isNotEmpty)
          await _localDb.deleteMany('invitations', toDelete);
      } else {
        // Davetler boş ise tabloyu temizle
        _localDb.clearTable('invitations');
      }
    });
  }

  Future<void> _syncAlarms(List<String> alarmIds) async {
    for (var id in alarmIds) {
      try {
        final snap = await _db
            .child('alarms')
            .child(id)
            .get()
            .timeout(const Duration(seconds: 3));
        if (snap.exists && snap.value is Map) {
          final data = Map<String, dynamic>.from(snap.value as Map);
          await _localDb.save('alarms', id, data);
        }
      } catch (e) {
        debugPrint(
          'Repository fetch alarm timeout / network fail (Cache will be used): $e',
        );
      }
    }

    // Yerelde kalmış ama kullanıcının artık içinde olmadığı alarmları sil (local_ ile başlayanları elleme)
    final localAlarms = await _localDb.getAll('alarms');
    final localIds = localAlarms.map((e) => e['id'] as String).toList();
    final toDelete = localIds
        .where((id) => !id.startsWith('local_') && !alarmIds.contains(id))
        .toList();
    if (toDelete.isNotEmpty) {
      await _localDb.deleteMany('alarms', toDelete);
    }
  }

  void _updateAlarmListeners(List<String> alarmIds) {
    // Önceden olup artık listede olmayan alarmları dinlemeyi kes
    final obsolete = _alarmSubs.keys
        .where((id) => !alarmIds.contains(id))
        .toList();
    for (var id in obsolete) {
      _alarmSubs[id]?.cancel();
      _alarmSubs.remove(id);
    }

    // Yeni alarmlar için individual onValue dinleyici ekle, anında SQLite'ı modifiye etsin
    for (var id in alarmIds) {
      if (!_alarmSubs.containsKey(id)) {
        _alarmSubs[id] = _db.child('alarms').child(id).onValue.listen((event) {
          if (event.snapshot.exists && event.snapshot.value is Map) {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            _localDb.save('alarms', id, data);
          } else {
            _localDb.delete('alarms', id);
          }
        });
      }
    }
  }

  void _removeAllAlarmListeners() {
    for (var sub in _alarmSubs.values) {
      sub.cancel();
    }
    _alarmSubs.clear();
  }

  // ============== EXPOSE STREAMS (UI SADECE BURAYI DİNLER) ================

  /// Offline bile olsa son halini Stream olarak UI'a verir
  Stream<List<Map<String, dynamic>>> get alarmsStream =>
      _localDb.watchTable('alarms');

  /// Gelen davetler. UI .watchTable() ile hep offline bile çalışabilir.
  Stream<List<Map<String, dynamic>>> get invitationsStream =>
      _localDb.watchTable('invitations');

  /// Aktif kullanıcının veya herhangi bir kullanıcının bilgilerini localden dinler
  Stream<Map<String, dynamic>?> watchUser(String uid) async* {
    await for (final users in _localDb.watchTable('users')) {
      yield users.where((e) => e['id'] == uid).firstOrNull;
    }
  }

  // Sadece okumak (bir kere) ve yoksa arka planda çekmek için
  Future<Map<String, dynamic>?> getUserOnce(String uid) async {
    final local = await _localDb.getById('users', uid);
    if (local == null) {
      // Offline değilsek getirmeye çalışalım (UI bloklanmasın diye kısa timeout)
      try {
        final snap = await _db
            .child('users')
            .child(uid)
            .get()
            .timeout(const Duration(seconds: 1));
        if (snap.exists && snap.value is Map) {
          final data = Map<String, dynamic>.from(snap.value as Map);
          await _localDb.save('users', uid, data);
          return data;
        }
      } catch (e) {
        // Offline error
      }
    } else {
      // Arka planda soft-update yap
      _db
          .child('users')
          .child(uid)
          .get()
          .then((snap) {
            if (snap.exists && snap.value is Map) {
              final data = Map<String, dynamic>.from(snap.value as Map);
              _localDb.save('users', uid, data);
            }
          })
          .catchError((_) {});
    }
    return local;
  }

  // Dispose temizlik
  void stopSync() {
    _currentUserSub?.cancel();
    _currentUserSub = null;
    _membershipsSub?.cancel();
    _membershipsSub = null;
    _invitationsSub?.cancel();
    _invitationsSub = null;
    _removeAllAlarmListeners();
  }
}
