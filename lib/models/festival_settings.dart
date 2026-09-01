// lib/models/festival_settings.dart

/// A single entry in a tenant's festival-wish list.
class FestivalEntry {
  /// Stable id used for idempotency/dedupe keying by the scheduled function.
  final String id;

  /// Display name, e.g. 'Diwali'.
  final String name;

  /// Festival date as an IST-local `YYYY-MM-DD` string (matches the shape the
  /// `sendFestivalWishes` server function compares against).
  final String date;

  /// Whether this festival should produce wishes. Disabled entries are skipped.
  final bool enabled;

  const FestivalEntry({
    required this.id,
    required this.name,
    required this.date,
    this.enabled = true,
  });

  factory FestivalEntry.fromMap(Map<String, dynamic> data, {String? id}) {
    return FestivalEntry(
      id: (data['id'] as String? ?? id ?? '').trim(),
      name: (data['name'] as String? ?? '').trim(),
      date: (data['date'] as String? ?? '').trim(),
      enabled: data['enabled'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'date': date, 'enabled': enabled};
  }

  FestivalEntry copyWith({
    String? id,
    String? name,
    String? date,
    bool? enabled,
  }) {
    return FestivalEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// Tenant `app_config/festival_settings` document model.
///
/// Mirrors the shape consumed by the `sendFestivalWishes` Cloud Function:
///   { enabled, advanceDays, festivals: [...], message: {...} }
/// The `message` templates support `{festival}`, `{companyName}`,
/// `{employeeName}` placeholders (server-side substitution).
class FestivalSettings {
  /// Master on/off switch. When false the scheduled job never sends for this
  /// tenant, regardless of the festival list.
  final bool enabled;

  /// Send wishes N calendar days BEFORE the festival date (0 = on the day).
  final int advanceDays;

  final List<FestivalEntry> festivals;

  /// Optional message templates; fall back to server defaults when empty.
  final String? title;
  final String? body;
  final String? emailSubject;
  final String? emailBody;

  const FestivalSettings({
    this.enabled = false,
    this.advanceDays = 0,
    this.festivals = const [],
    this.title,
    this.body,
    this.emailSubject,
    this.emailBody,
  });

  factory FestivalSettings.fromMap(Map<String, dynamic> data) {
    final rawFestivals = data['festivals'];
    final rawMessage = data['message'];
    final message = rawMessage is Map
        ? Map<String, dynamic>.from(rawMessage)
        : const <String, dynamic>{};
    return FestivalSettings(
      enabled: data['enabled'] == true,
      advanceDays: data['advanceDays'] is num
          ? (data['advanceDays'] as num).toInt()
          : 0,
      festivals: rawFestivals is List
          ? rawFestivals
                .whereType<Map>()
                .map((f) => FestivalEntry.fromMap(Map<String, dynamic>.from(f)))
                .toList()
          : const <FestivalEntry>[],
      title: message['title'] as String? ?? data['title'] as String?,
      body: message['body'] as String? ?? data['body'] as String?,
      emailSubject: message['emailSubject'] as String?,
      emailBody: message['emailBody'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'advanceDays': advanceDays,
      'festivals': festivals.map((f) => f.toMap()).toList(),
      'message': {
        if (title != null && title!.isNotEmpty) 'title': title,
        if (body != null && body!.isNotEmpty) 'body': body,
        if (emailSubject != null && emailSubject!.isNotEmpty)
          'emailSubject': emailSubject,
        if (emailBody != null && emailBody!.isNotEmpty) 'emailBody': emailBody,
      },
    };
  }

  FestivalSettings copyWith({
    bool? enabled,
    int? advanceDays,
    List<FestivalEntry>? festivals,
    String? title,
    String? body,
    String? emailSubject,
    String? emailBody,
  }) {
    return FestivalSettings(
      enabled: enabled ?? this.enabled,
      advanceDays: advanceDays ?? this.advanceDays,
      festivals: festivals ?? this.festivals,
      title: title ?? this.title,
      body: body ?? this.body,
      emailSubject: emailSubject ?? this.emailSubject,
      emailBody: emailBody ?? this.emailBody,
    );
  }
}
