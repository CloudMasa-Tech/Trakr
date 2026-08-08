import 'package:cloud_firestore/cloud_firestore.dart';

/// Billing state of a workspace subscription (platform-level data).
enum SubscriptionStatus {
  trialing,
  active,
  pastDue,
  canceled,
  paused,
  unpaid;

  /// The wire value stored in Firestore.
  String get value {
    switch (this) {
      case SubscriptionStatus.trialing:
        return 'trialing';
      case SubscriptionStatus.active:
        return 'active';
      case SubscriptionStatus.pastDue:
        return 'past_due';
      case SubscriptionStatus.canceled:
        return 'canceled';
      case SubscriptionStatus.paused:
        return 'paused';
      case SubscriptionStatus.unpaid:
        return 'unpaid';
    }
  }

  /// Human-readable label for UI.
  String get label {
    switch (this) {
      case SubscriptionStatus.trialing:
        return 'Trialing';
      case SubscriptionStatus.active:
        return 'Active';
      case SubscriptionStatus.pastDue:
        return 'Past Due';
      case SubscriptionStatus.canceled:
        return 'Canceled';
      case SubscriptionStatus.paused:
        return 'Paused';
      case SubscriptionStatus.unpaid:
        return 'Unpaid';
    }
  }

  /// Parses a stored value back into a [SubscriptionStatus], or `null` for
  /// unknown values.
  static SubscriptionStatus? fromValue(String? value) {
    switch (value) {
      case 'trialing':
        return SubscriptionStatus.trialing;
      case 'active':
        return SubscriptionStatus.active;
      case 'past_due':
      case 'pastDue':
        return SubscriptionStatus.pastDue;
      case 'canceled':
        return SubscriptionStatus.canceled;
      case 'paused':
        return SubscriptionStatus.paused;
      case 'unpaid':
        return SubscriptionStatus.unpaid;
      default:
        return null;
    }
  }
}

/// Billing cadence of a subscription.
enum BillingCycle {
  monthly,
  annual;

  /// The wire value stored in Firestore.
  String get value {
    switch (this) {
      case BillingCycle.monthly:
        return 'monthly';
      case BillingCycle.annual:
        return 'annual';
    }
  }

  /// Human-readable label for UI.
  String get label {
    switch (this) {
      case BillingCycle.monthly:
        return 'Monthly';
      case BillingCycle.annual:
        return 'Annual';
    }
  }

  /// Parses a stored value back into a [BillingCycle], or `null` for unknown
  /// values.
  static BillingCycle? fromValue(String? value) {
    switch (value) {
      case 'monthly':
        return BillingCycle.monthly;
      case 'annual':
        return BillingCycle.annual;
      default:
        return null;
    }
  }
}

/// The billing subscription attached to a workspace.
///
/// Stored embedded in the `workspaces/{workspaceId}` document so the registry
/// entry stays self-contained and atomic; it may later move to its own
/// `subscriptions/{subscriptionId}` collection.
class Subscription {
  /// External subscription id (e.g. from a billing provider), if any.
  final String? subscriptionId;

  /// The plan this subscription is on (`plans/{planId}`).
  final String planId;

  /// Denormalized plan name for display without a plans join.
  final String planName;

  final SubscriptionStatus status;
  final BillingCycle billingCycle;

  /// Currently billed amount in [currency].
  final double price;

  /// ISO 4217 currency code, e.g. "USD".
  final String currency;

  /// Number of seats (employees) this subscription covers.
  final int seats;

  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? startedAt;
  final DateTime? trialEndsAt;
  final DateTime? canceledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Subscription({
    this.subscriptionId,
    required this.planId,
    required this.planName,
    this.status = SubscriptionStatus.active,
    this.billingCycle = BillingCycle.monthly,
    this.price = 0,
    this.currency = 'USD',
    this.seats = 0,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.startedAt,
    this.trialEndsAt,
    this.canceledAt,
    this.createdAt,
    this.updatedAt,
  });

  /// A minimal, empty subscription used before a plan is chosen.
  const Subscription.empty()
      : subscriptionId = null,
        planId = '',
        planName = '',
        status = SubscriptionStatus.active,
        billingCycle = BillingCycle.monthly,
        price = 0,
        currency = 'USD',
        seats = 0,
        currentPeriodStart = null,
        currentPeriodEnd = null,
        startedAt = null,
        trialEndsAt = null,
        canceledAt = null,
        createdAt = null,
        updatedAt = null;

  factory Subscription.fromMap(Map<String, dynamic> data) {
    return Subscription(
      subscriptionId: data['subscriptionId'] as String?,
      planId: data['planId'] as String? ?? '',
      planName: data['planName'] as String? ?? '',
      status: SubscriptionStatus.fromValue(data['status'] as String?) ??
          SubscriptionStatus.active,
      billingCycle: BillingCycle.fromValue(data['billingCycle'] as String?) ??
          BillingCycle.monthly,
      price: (data['price'] as num?)?.toDouble() ?? 0,
      currency: data['currency'] as String? ?? 'USD',
      seats: (data['seats'] as num?)?.toInt() ?? 0,
      currentPeriodStart: _timestamp(data['currentPeriodStart']),
      currentPeriodEnd: _timestamp(data['currentPeriodEnd']),
      startedAt: _timestamp(data['startedAt']),
      trialEndsAt: _timestamp(data['trialEndsAt']),
      canceledAt: _timestamp(data['canceledAt']),
      createdAt: _timestamp(data['createdAt']),
      updatedAt: _timestamp(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (subscriptionId != null) 'subscriptionId': subscriptionId,
      'planId': planId,
      'planName': planName,
      'status': status.value,
      'billingCycle': billingCycle.value,
      'price': price,
      'currency': currency,
      'seats': seats,
      if (currentPeriodStart != null)
        'currentPeriodStart': Timestamp.fromDate(currentPeriodStart!),
      if (currentPeriodEnd != null)
        'currentPeriodEnd': Timestamp.fromDate(currentPeriodEnd!),
      if (startedAt != null) 'startedAt': Timestamp.fromDate(startedAt!),
      if (trialEndsAt != null) 'trialEndsAt': Timestamp.fromDate(trialEndsAt!),
      if (canceledAt != null) 'canceledAt': Timestamp.fromDate(canceledAt!),
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  /// Whether the workspace currently has access under this subscription.
  bool get isEntitled =>
      status == SubscriptionStatus.active ||
      status == SubscriptionStatus.trialing;

  Subscription copyWith({
    String? subscriptionId,
    String? planId,
    String? planName,
    SubscriptionStatus? status,
    BillingCycle? billingCycle,
    double? price,
    String? currency,
    int? seats,
    DateTime? currentPeriodStart,
    DateTime? currentPeriodEnd,
    DateTime? startedAt,
    DateTime? trialEndsAt,
    DateTime? canceledAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Subscription(
      subscriptionId: subscriptionId ?? this.subscriptionId,
      planId: planId ?? this.planId,
      planName: planName ?? this.planName,
      status: status ?? this.status,
      billingCycle: billingCycle ?? this.billingCycle,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      seats: seats ?? this.seats,
      currentPeriodStart: currentPeriodStart ?? this.currentPeriodStart,
      currentPeriodEnd: currentPeriodEnd ?? this.currentPeriodEnd,
      startedAt: startedAt ?? this.startedAt,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      canceledAt: canceledAt ?? this.canceledAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _timestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is DateTime) return value;
    return null;
  }
}
