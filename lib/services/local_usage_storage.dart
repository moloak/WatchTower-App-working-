import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/app_usage_model.dart';

class LocalUsageStorage {
  LocalUsageStorage._internal();
  static final LocalUsageStorage instance = LocalUsageStorage._internal();

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'usage_local.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE daily_usage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            packageName TEXT NOT NULL,
            appName TEXT,
            minutes INTEGER NOT NULL,
            iconBase64 TEXT,
            lastUpdated INTEGER
          );
        ''');

        await db.execute('''
          CREATE TABLE pushed_weeks (
            weekStart TEXT PRIMARY KEY,
            pushedAt INTEGER
          );
        ''');
      },
    );
  }

  Future<void> saveDailyUsage(String date, AppUsageModel app) async {
    if (_db == null) await init();
    final minutes = app.currentUsage.inMinutes;
    final iconBase64 = app.iconBytes != null ? base64Encode(app.iconBytes!) : null;

    final existing = await _db!.query(
      'daily_usage',
      columns: ['id', 'minutes'],
      where: 'date = ? AND packageName = ?',
      whereArgs: [date, app.packageName],
    );

    if (existing.isNotEmpty) {
      // update minutes (take latest)
      await _db!.update(
        'daily_usage',
        {
          'minutes': minutes,
          'appName': app.appName,
          'iconBase64': iconBase64,
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'date = ? AND packageName = ?',
        whereArgs: [date, app.packageName],
      );
    } else {
      await _db!.insert('daily_usage', {
        'date': date,
        'packageName': app.packageName,
        'appName': app.appName,
        'minutes': minutes,
        'iconBase64': iconBase64,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });
    }

    // If the user is signed in, also write the daily usage to Firestore so
    // server-side aggregation can operate on per-day docs.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('daily_usage')
            .doc(date)
            .set({
          'date': date,
          'packageName': app.packageName,
          'appName': app.appName,
          'minutes': minutes,
          'iconBase64': iconBase64,
          'lastUpdated': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      } catch (e) {
        // ignore: avoid_print
  debugPrint('Failed to write daily usage to Firestore: $e');
      }
    }
  }

  Future<Map<String, int>> getWeeklyAggregate(DateTime weekStart) async {
    if (_db == null) await init();
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final dates = List.generate(7, (i) => _formatDate(start.add(Duration(days: i))));

    final placeholders = dates.map((_) => '?').join(',');
    final rows = await _db!.rawQuery(
      'SELECT packageName, appName, SUM(minutes) as total FROM daily_usage WHERE date IN ($placeholders) GROUP BY packageName, appName',
      dates,
    );

    final Map<String, int> result = {};
    for (final r in rows) {
      final pkg = r['packageName'] as String;
      final total = (r['total'] as int?) ?? 0;
      result[pkg] = total;
    }
    return result;
  }

  Future<bool> hasPushedWeek(DateTime weekStart) async {
    if (_db == null) await init();
    final ws = _formatDate(weekStart);
    final rows = await _db!.query('pushed_weeks', where: 'weekStart = ?', whereArgs: [ws]);
    return rows.isNotEmpty;
  }

  Future<void> markWeekPushed(DateTime weekStart) async {
    if (_db == null) await init();
    final ws = _formatDate(weekStart);
    await _db!.insert('pushed_weeks', {'weekStart': ws, 'pushedAt': DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> pushWeeklySummaryIfDue() async {
    if (_db == null) await init();
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1)); // Monday

    final already = await hasPushedWeek(weekStart);
    if (already) return;

    final aggregate = await getWeeklyAggregate(weekStart);
    if (aggregate.isEmpty) {
      await markWeekPushed(weekStart);
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final payload = {
      'weekStart': _formatDate(weekStart),
      'generatedAt': DateTime.now().toIso8601String(),
      'apps': aggregate.map((k, v) => MapEntry(k, v)),
    };

    // Attempt to POST the weekly summary to the server-side Cloud Function.
    // The function should verify the user's Firebase ID token and write the
    // summary to Firestore server-side. If posting fails (for example no id
    // token available in a background isolate), fall back to writing directly
    // to Firestore from the device.
    const functionsUrl = String.fromEnvironment('WEEKLY_SUMMARY_URL', defaultValue: 'https://<YOUR_REGION>-<YOUR_PROJECT>.cloudfunctions.net/pushWeeklySummary');

    bool pushed = false;
    if (uid != null) {
      try {
        final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (idToken != null) {
          final resp = await http.post(
            Uri.parse(functionsUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 30));

          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            pushed = true;
          } else {
            // ignore: avoid_print
            debugPrint('Weekly summary POST failed: ${resp.statusCode} ${resp.body}');
          }
        }
      } catch (e) {
        // ignore: avoid_print
  debugPrint('Error posting weekly summary: $e');
      }
    }

    if (!pushed) {
      // Fallback to writing directly to Firestore under the user's doc if
      // we couldn't call the Cloud Function (e.g., no auth token in background).
      if (uid != null) {
        final docRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('weekly_summaries').doc(_formatDate(weekStart));
        await docRef.set(payload);
        pushed = true;
      }
    }

    if (pushed) {
      await markWeekPushed(weekStart);
    }
  }

  String _formatDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
