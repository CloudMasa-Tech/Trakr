import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import 'notification_service.dart';

class AnniversaryGreeting {
  final String id;
  final String recipient;
  final String employeeName;
  final String companyName;
  final int yearsCompleted;
  final String title;
  final String message;
  final DateTime timestamp;

  const AnniversaryGreeting({
    required this.id,
    required this.recipient,
    required this.employeeName,
    required this.companyName,
    required this.yearsCompleted,
    required this.title,
    required this.message,
    required this.timestamp,
  });
}

class AnniversaryGreetingService {
  AnniversaryGreetingService({FirebaseContext? context})
      : _firestore = (context ?? FirebaseContextProvider.current).firestore;

  final FirebaseFirestore _firestore;

  Future<AnniversaryGreeting?> createTodayGreetingIfDue({
    required String profileId,
    required String recipient,
    required String employeeName,
    required DateTime? joinDate,
    required String companyName,
    required String role,
    Iterable<String> audienceIds = const [],
  }) async {
    if (joinDate == null) return null;

    final now = DateTime.now();
    final anniversaryYears = _completedYears(joinDate, now);
    if (anniversaryYears <= 0 || !_isAnniversaryToday(joinDate, now)) {
      return null;
    }

    final safeProfileId = _safeId(
      profileId.trim().isNotEmpty ? profileId : recipient,
    );
    final notificationId = 'anniversary_${safeProfileId}_${now.year}';
    final cleanCompany = companyName.trim().isEmpty
        ? NotificationService.brand
        : companyName.trim();
    final cleanName =
        employeeName.trim().isEmpty ? 'Team member' : employeeName;
    const title = 'Work Anniversary';
    final message =
        'Congratulations $cleanName, you have completed $anniversaryYears '
        '${anniversaryYears == 1 ? 'year' : 'years'} in $cleanCompany.';
    final timestamp = now;

    final docRef = _firestore.collection('notifications').doc(notificationId);
    final audience = audienceIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    return _firestore.runTransaction<AnniversaryGreeting?>((transaction) async {
      final existing = await transaction.get(docRef);
      if (existing.exists) {
        final data = existing.data() ?? {};
        if (data['celebrationShownAt'] != null) return null;

        transaction.update(docRef, {
          'celebrationShownAt': FieldValue.serverTimestamp(),
        });

        return _greetingFromData(
          id: notificationId,
          data: data,
          fallbackRecipient: recipient,
          fallbackEmployeeName: cleanName,
          fallbackCompanyName: cleanCompany,
          fallbackYearsCompleted: anniversaryYears,
          fallbackTitle: title,
          fallbackMessage: message,
          fallbackTimestamp: timestamp,
        );
      }

      transaction.set(docRef, {
        'recipient': recipient,
        'type': 'Work Anniversary',
        'title': title,
        'content': message,
        'employeeName': cleanName,
        'userName': cleanName,
        'status': 'Sent',
        'suppressFirestorePush': true,
        'allowFirestorePush': false,
        'timestamp': FieldValue.serverTimestamp(),
        'celebrationShownAt': FieldValue.serverTimestamp(),
        'actionType': 'work_anniversary',
        'role': role,
        'companyName': cleanCompany,
        'yearsCompleted': anniversaryYears,
        'joinDate': Timestamp.fromDate(joinDate),
        'audienceIds': audience,
      });

      return AnniversaryGreeting(
        id: notificationId,
        recipient: recipient,
        employeeName: cleanName,
        companyName: cleanCompany,
        yearsCompleted: anniversaryYears,
        title: title,
        message: message,
        timestamp: timestamp,
      );
    });
  }

  AnniversaryGreeting _greetingFromData({
    required String id,
    required Map<String, dynamic> data,
    required String fallbackRecipient,
    required String fallbackEmployeeName,
    required String fallbackCompanyName,
    required int fallbackYearsCompleted,
    required String fallbackTitle,
    required String fallbackMessage,
    required DateTime fallbackTimestamp,
  }) {
    return AnniversaryGreeting(
      id: id,
      recipient: (data['recipient'] ?? fallbackRecipient).toString(),
      employeeName:
          (data['employeeName'] ?? data['userName'] ?? fallbackEmployeeName)
              .toString(),
      companyName: (data['companyName'] ?? fallbackCompanyName).toString(),
      yearsCompleted:
          (data['yearsCompleted'] as num?)?.toInt() ?? fallbackYearsCompleted,
      title: (data['title'] ?? fallbackTitle).toString(),
      message: (data['content'] ?? fallbackMessage).toString(),
      timestamp: _timestampFrom(data['timestamp']) ?? fallbackTimestamp,
    );
  }

  int _completedYears(DateTime joinDate, DateTime today) {
    var years = today.year - joinDate.year;
    final anniversaryThisYear = _anniversaryDateForYear(joinDate, today.year);
    if (today.isBefore(anniversaryThisYear)) years--;
    return years;
  }

  bool _isAnniversaryToday(DateTime joinDate, DateTime today) {
    if (joinDate.month == 2 && joinDate.day == 29) {
      final isLeapYear = today.year % 4 == 0 &&
          (today.year % 100 != 0 || today.year % 400 == 0);
      if (!isLeapYear) return today.month == 2 && today.day == 28;
    }
    return joinDate.month == today.month && joinDate.day == today.day;
  }

  DateTime _anniversaryDateForYear(DateTime joinDate, int year) {
    if (joinDate.month == 2 && joinDate.day == 29) {
      final isLeapYear = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
      if (!isLeapYear) return DateTime(year, 2, 28);
    }
    return DateTime(year, joinDate.month, joinDate.day);
  }

  DateTime? _timestampFrom(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _safeId(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return sanitized.isEmpty ? 'user' : sanitized;
  }
}
