import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import '../model/call_record.dart';

final callRepositoryProvider = Provider((ref) => CallRepository());

class CallRepository {
  static const storageKey = 'call_assist_records_v1';
  static final _lock = Lock();

  Future<List<CallRecord>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(storageKey);
    if (raw == null) return [];
    // A corrupt store must remain intact, rather than being replaced silently.
    return (jsonDecode(raw) as List)
        .map((j) => CallRecord.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> save(CallRecord record) => _lock.synchronized(() async {
    final records = await load();
    records.removeWhere((r) => r.id == record.id);
    records.add(record);
    await _write(records);
  });

  Future<void> _write(List<CallRecord> records) async {
    final ok = await (await SharedPreferences.getInstance()).setString(
      storageKey,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
    if (!ok) throw StateError('Could not save call record');
  }

  Future<bool> recordingExists(String path) async =>
      await File(path).exists() && await File(path).length() > 0;

  /// Delete owned audio first. Keep the entry available for retry on failure.
  Future<void> delete(String id) => _lock.synchronized(() async {
    final records = await load();
    final target = records.where((r) => r.id == id).firstOrNull;
    if (target == null) return;
    final root = p.normalize(
      p.join((await getApplicationDocumentsDirectory()).path, 'recordings'),
    );
    final otherPaths = records
        .where((r) => r.id != id)
        .expand((r) => r.recordings)
        .map((r) => r.path)
        .toSet();
    for (final clip in target.recordings) {
      final normalized = p.normalize(clip.path);
      if (otherPaths.contains(clip.path)) continue;
      if (p.dirname(normalized) != root ||
          !p.basename(normalized).startsWith('call_assist_')) {
        throw StateError('Recording is outside the call recording directory');
      }
      final file = File(normalized);
      if (await file.exists()) await file.delete();
    }
    await _write(records.where((r) => r.id != id).toList());
  });
}
