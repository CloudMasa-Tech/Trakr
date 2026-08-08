import '../../utils/departments.dart';

/// Default designation titles seeded into a fresh tenant project. The
/// Company Admin can extend these later; staff/manager records store their own
/// designation strings, so this catalog is a starting point for onboarding.
const List<String> kTenantDefaultDesignations = <String>[
  'Administrator',
  'Manager',
  'Team Lead',
  'Executive',
  'Engineer',
  'Analyst',
  'Associate',
  'Trainee',
];

/// Default departments seeded into a fresh tenant project. Reuses the app-wide
/// canonical list so directory screens and filters match out of the box.
const List<String> kTenantDefaultDepartments = kAppDepartments;

/// Default leave policies seeded into a fresh tenant project. Mirrors the
/// app-level `LeaveService.monthlyLeaveAllowance` constant so the balance math
/// behaves the same on day one.
const List<Map<String, dynamic>> kTenantDefaultLeavePolicies =
    <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'default',
    'name': 'Default Leave Policy',
    'monthlyLeaveAllowance': 1,
    'isDefault': true,
    'isActive': true,
  },
];

/// Default working-week + holiday calendar. Weekends are Sat/Sun off with no
/// public holidays pre-loaded; the tenant admin configures its own holidays.
const Map<String, dynamic> kTenantDefaultHolidayCalendar = <String, dynamic>{
  'saturdayWorking': true,
  'sundayWorking': false,
  'holidayDates': <String>[],
  'holidayEvents': <Map<String, dynamic>>[],
};

/// Geofence radius used by the default office / attendance settings. The code
/// default is 50m (not the 100m claimed in older README text).
const double kTenantDefaultGeoFenceRadius = 50.0;

const String kTenantDefaultCheckInStart = '08:30 AM';
const String kTenantDefaultCheckInEnd = '10:30 AM';
const String kTenantDefaultCheckOutStart = '05:00 PM';
const String kTenantDefaultCheckOutEnd = '07:30 PM';

/// Default brand color applied to a fresh tenant (matches the onboarding
/// primary color used by `CompanyService`).
const String kTenantDefaultPrimaryColorHex = '0F766E';
