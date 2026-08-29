import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:attendqr/firebase_options.dart';

/// A script to backfill `canBeReportingManager` for existing roles and verify admins.
/// Run this with: `flutter run -t scripts/backfill_manager_roles.dart -d chrome`
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const BackfillApp());
}

class BackfillApp extends StatelessWidget {
  const BackfillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: BackfillScreen(),
    );
  }
}

class BackfillScreen extends StatefulWidget {
  const BackfillScreen({super.key});

  @override
  State<BackfillScreen> createState() => _BackfillScreenState();
}

class _BackfillScreenState extends State<BackfillScreen> {
  final List<String> _logs = [];
  bool _isRunning = false;

  void _log(String message) {
    setState(() {
      _logs.add('${DateTime.now().toIso8601String()} - $message');
    });
  }

  Future<void> _runBackfill() async {
    setState(() {
      _isRunning = true;
      _logs.clear();
    });

    try {
      _log('Starting backfill...');
      final db = FirebaseFirestore.instance;

      _log('Querying roles collection...');
      final rolesSnap = await db.collection('roles').get();
      
      int updatedRoles = 0;
      final batch = db.batch();

      for (final roleDoc in rolesSnap.docs) {
        final data = roleDoc.data();
        final name = data['name']?.toString().toLowerCase() ?? '';
        final id = roleDoc.id.toLowerCase();

        // Default: Company Admin and Manager get true, others get false.
        bool canBeReportingManager = false;
        int level = 10;
        if (name.contains('admin') && name.contains('company')) {
          canBeReportingManager = true;
          level = 100;
        } else if (id == 'manager' || name == 'manager' || name.contains('team lead')) {
          canBeReportingManager = true;
          level = 60;
        } else if (id == 'hr' || name == 'hr') {
          level = 40;
        } else if (id == 'payroll_admin' || name == 'payroll admin') {
          level = 60;
        }

        final updates = <String, dynamic>{};
        if (data['canBeReportingManager'] == null) {
          updates['canBeReportingManager'] = canBeReportingManager;
        }
        if (data['level'] == null) {
          updates['level'] = level;
        }

        if (updates.isNotEmpty) {
          updatedRoles++;
          batch.update(roleDoc.reference, updates);
          _log('Scheduled update for role: ${data['name']} ($updates)');
        }
      }

      if (updatedRoles > 0) {
        await batch.commit();
        _log('Successfully updated $updatedRoles roles.');
      } else {
        _log('No roles needed updating.');
      }

      _log('Backfill complete!');
    } catch (e, st) {
      _log('Error: $e\n$st');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backfill Manager Roles')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _isRunning ? null : _runBackfill,
              child: const Text('Run Backfill'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(8),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, i) => Text(
                    _logs[i],
                    style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
