import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String recipient;
  final String type;
  final String title;
  final String content;
  final String employeeName;
  final String actionType;
  final String requestId;
  final String requestCollection;
  final String status;
  final DateTime timestamp;

  NotificationModel({
    required this.id,
    required this.recipient,
    required this.type,
    required this.title,
    required this.content,
    required this.employeeName,
    this.actionType = '',
    this.requestId = '',
    this.requestCollection = '',
    required this.status,
    required this.timestamp,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      recipient: data['recipient'] ?? '',
      type: data['type'] ??
          data['notificationType'] ??
          data['actionType'] ??
          'Notification',
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      employeeName: data['employeeName'] ?? data['userName'] ?? '',
      actionType: data['actionType'] ?? '',
      requestId: data['requestId'] ?? '',
      requestCollection: data['requestCollection'] ?? '',
      status: data['status'] ?? 'Sent',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'recipient': recipient,
      'type': type,
      'title': title,
      'content': content,
      'employeeName': employeeName,
      'actionType': actionType,
      'requestId': requestId,
      'requestCollection': requestCollection,
      'status': status,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
