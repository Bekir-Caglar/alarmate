import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDb {
  static final LocalDb instance = LocalDb._init();
  static Database? _database;

  LocalDb._init();

  Future<String> getActiveUid() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) return user.uid;

    final prefs = await SharedPreferences.getInstance();
    String? localId = prefs.getString('local_guest_id');
    if (localId == null) {
      localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('local_guest_id', localId);
    }
    return localId;
  }

  final Map<String, StreamController<List<Map<String, dynamic>>>> _controllers =
      {};

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('alarmate_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const jsonType = 'TEXT NOT NULL';

    await db.execute('''
CREATE TABLE alarms (
  id $idType,
  json_data $jsonType
)
''');
    await db.execute('''
CREATE TABLE invitations (
  id $idType,
  json_data $jsonType
)
''');
    await db.execute('''
CREATE TABLE users (
  id $idType,
  json_data $jsonType
)
''');
  }

  // Reactive Stream
  Stream<List<Map<String, dynamic>>> watchTable(String table) async* {
    if (!_controllers.containsKey(table)) {
      _controllers[table] =
          StreamController<List<Map<String, dynamic>>>.broadcast();
    }
    yield await getAll(table); // Instantly supply cached data
    yield* _controllers[table]!.stream; // Then stream future updates
  }

  final Map<String, Timer?> _notifyTimers = {};

  void _notifyListeners(String table) {
    if (_controllers.containsKey(table)) {
      _notifyTimers[table]?.cancel();
      _notifyTimers[table] = Timer(const Duration(milliseconds: 100), () async {
        if (_controllers[table]?.isClosed ?? true) return;
        final items = await getAll(table);
        if (_controllers.containsKey(table) && !_controllers[table]!.isClosed) {
          _controllers[table]!.add(items);
        }
      });
    }
  }

  Future<List<Map<String, dynamic>>> getAll(String table) async {
    final db = await instance.database;
    final maps = await db.query(table);
    final uid = await getActiveUid();

    final results = <Map<String, dynamic>>[];
    for (var e in maps) {
      final data = jsonDecode(e['json_data'] as String) as Map<String, dynamic>;
      data['id'] = e['id']; // Inject key if missing

      if (table == 'users') {
        results.add(data);
      } else {
        final owner = data['_owner_uid'];
        if (owner == uid) {
          results.add(data);
        } else if (owner == null) {
          // Geriye dönük uyumluluk: Sahibi olmayan eski verileri mevcut kullanıcıya (Anonim veya Auth) ata
          data['_owner_uid'] = uid;
          await db.update(
            table,
            {'json_data': jsonEncode(data)},
            where: 'id = ?',
            whereArgs: [data['id']],
          );
          results.add(data);
        }
      }
    }
    return results;
  }

  Future<Map<String, dynamic>?> getById(String table, String id) async {
    final db = await instance.database;
    final maps = await db.query(table, where: 'id = ?', whereArgs: [id]);
    final uid = await getActiveUid();

    if (maps.isNotEmpty) {
      final data =
          jsonDecode(maps.first['json_data'] as String) as Map<String, dynamic>;
      data['id'] = id;

      if (table == 'users') return data;

      final owner = data['_owner_uid'];
      if (owner == uid) {
        return data;
      } else if (owner == null) {
        data['_owner_uid'] = uid;
        await db.update(
          table,
          {'json_data': jsonEncode(data)},
          where: 'id = ?',
          whereArgs: [id],
        );
        return data;
      }
      return null;
    }
    return null;
  }

  Future<void> save(String table, String id, Map<String, dynamic> data) async {
    final db = await instance.database;
    data['id'] = id; // Normalization
    if (table != 'users') {
      data['_owner_uid'] = await getActiveUid();
    }
    await db.insert(table, {
      'id': id,
      'json_data': jsonEncode(data),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _notifyListeners(table);
  }

  // Save multiple at once
  Future<void> saveAll(
    String table,
    Map<String, Map<String, dynamic>> items,
  ) async {
    final db = await instance.database;
    final uid = await getActiveUid();
    final batch = db.batch();
    for (var entry in items.entries) {
      final data = entry.value;
      data['id'] = entry.key;
      if (table != 'users') data['_owner_uid'] = uid;
      batch.insert(table, {
        'id': entry.key,
        'json_data': jsonEncode(data),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    _notifyListeners(table);
  }

  Future<void> delete(String table, String id) async {
    final db = await instance.database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
    _notifyListeners(table);
  }

  // Use to clear items that are deleted from cloud
  Future<void> deleteMany(String table, List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (var id in ids) {
      batch.delete(table, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    _notifyListeners(table);
  }

  Future<void> clearTable(String table) async {
    final db = await instance.database;

    if (table != 'users') {
      final items = await getAll(table);
      final ids = items.map((e) => e['id'] as String).toList();
      if (ids.isNotEmpty) {
        final batch = db.batch();
        for (final id in ids) {
          batch.delete(table, where: 'id = ?', whereArgs: [id]);
        }
        await batch.commit(noResult: true);
      }
    } else {
      await db.delete(table);
    }
    _notifyListeners(table);
  }
}
