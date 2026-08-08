# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**TЯAKR** (package name `attendqr`, README title "AttendQR Enterprise") — a multi-tenant, white-labelled Flutter QR/geofence attendance-management system with a Firebase backend (Auth, Firestore, Cloud Messaging) plus a Vercel serverless backend for push/email/cron. Targets Android, iOS, web, Windows, macOS, Linux.

## Common Development Commands

- **Install dependencies**: `flutter pub get`
- **Run the app (debug)**: `flutter run` (pass `-d chrome`, `-d windows`, `-d macos`, etc.)
- **Run tests**: `flutter test` — only the default `test/widget_test.dart` stub exists; there is no real test suite.
- **Static analysis / lint**: `flutter analyze`
- **Build Android APK**: `flutter build apk --release`
- **Build iOS app**: `flutter build ios --release`
- **Build web**: `flutter build web`
- **Regenerate launcher icons**: `flutter pub run flutter_launcher_icons` (config at the bottom of `pubspec.yaml`, source image `assets/trakr00-removebg-preview.png`)
- **Vercel backend** (in `vercel_backend/`, Node.js serverless functions): deploy the whole directory with `vercel deploy --prod` from `vercel_backend/`. It runs on the **Spark plan** — all server-side push, email, and scheduled jobs live here. Requires the `FIREBASE_SERVICE_ACCOUNT` env var (a JSON service-account key) plus `SMTP_EMAIL`/`SMTP_PASSWORD` for `sendCredentialEmail`.
- **Firestore rules/indexes**: `firebase deploy --only firestore:rules,firestore:indexes`

## Architecture

### State management (Provider, not Bloc/Riverpod)
`lib/main.dart` wires a `MultiProvider` with exactly two `ChangeNotifierProvider`s, both created before the first frame:

- **`WhiteLabelProvider`** (`lib/providers/white_label_provider.dart`) — streams a Firestore tenant-config doc via `WhiteLabelService` and rebuilds `MaterialApp.theme` live. Branding (colors, logo, company name) is data-driven. The whole app is wrapped in a `Consumer<WhiteLabelProvider>` so any config change re-themes the UI instantly.
- **`AuthSessionProvider`** (`lib/providers/auth_session_provider.dart`) — owns `FirebaseAuth` + Google Sign-In session state, resolves the signed-in user's **role**, and caches it in `shared_preferences` for fast restarts.

Routing is `MaterialApp.routes`, with `AuthGateScreen` (`lib/screens/auth/auth_gate_screen.dart`) as the entry point that dispatches to a role-specific home screen.

### Roles
`AppUserRole` enum (in `auth_session_provider.dart`) has exactly three values: **`admin`**, **`manager`**, **`engineer`** (the "staff"/employee role — `fromValue()` also accepts the legacy string `'staff'` for backward compatibility with old Firestore docs).

### Screen folders (`lib/screens/`)
- `auth/` — `login_screen.dart`, `forgot_password_screen.dart`, `auth_gate_screen.dart` (role dispatcher), `auth_shared.dart`
- `staff/` — `staff_scan_qr_screen.dart` (core check-in/out path), `staff_leave_screen.dart`, `checkout_request_screen.dart`
- `manager/` — `manager_dashboard_screen.dart`, `manager_team_members_screen.dart`, `onboard_user_dialog.dart`
- `admin/` — `team_directory_screen.dart`, `attendance_history_screen.dart`, `manager_team_screen.dart`, `manager_requests_screen.dart`, `manager_attendance_log_screen.dart`, `monthly_analysis_screen.dart`, `monthly_employee_analysis_screen.dart`, `notifications_history_screen.dart`, `payroll_screen.dart`, `weekend_holiday_screen.dart`, `white_label_screen.dart` (tenant branding editor)
- `dashboard/attendance_dashboard_screen.dart` — shared analytics dashboard
- `employee/employee_home_screen.dart`, `leave/leave_approval_screen.dart`, `geo_tag/geo_tag_screen.dart`, `landing/landing_page.dart`, `multi_view/multi_model_view_screen.dart`, `app_shell.dart` (nav shell/scaffold)

### QR + geofence flow
1. Staff opens `staff_scan_qr_screen.dart` and scans via `widgets/attendance/qr_attendance_scanner.dart`.
2. The scanner accepts **two QR payload formats**: JSON `{token, employeeId}` or query string `token=…&employeeId=…`.
3. The screen reads device GPS, fetches the relevant office's `offices`/`geo_config` doc from Firestore, and checks distance against a radius. **Default is 50m** (`_radiusInMeters = 50.0` in `staff_scan_qr_screen.dart`), overridable per-office via the stored `radius` field. `GeoFenceService.validationRadius()` centralizes the effective-radius calculation (accounts for GPS accuracy + safety margin).
4. Submission goes through `AttendanceService.markAttendance(...)` (client, `lib/services/attendance_service.dart`) which validates the QR token and geofence directly against Firestore — there is no server-side callable in the Spark-only architecture.
5. The Vercel cron `/api/qrNotifications` (in `vercel_backend/vercel.json`, daily at 3 AM) rotates per-tenant tokens in `qr_tokens` (90-day expiry window logic baked in).

Note: `lib/services/qr_service.dart` exists but is **empty (0 lines)** — all QR logic actually lives in `qr_attendance_scanner.dart`, `staff_scan_qr_screen.dart`, and `AttendanceService`.

### Attendance state machine
`AttendanceState` enum (`lib/models/attendance_model.dart`): `NONE → CHECK_IN → TEMP_EXIT → RE_ENTRY → FINAL_CHECKOUT`, plus an `UNAUTHORIZED_EXIT` branch. Mirrored by `AttendanceEventType` in `attendance_log.dart` for the immutable audit trail (`attendance_logs` collection). Absence thresholds are constants on `AttendanceModel`: `halfDayAbsentMinutes = 180`, `fullDayAbsentMinutes = 360`.

### Services layer (`lib/services/`) — singleton-style Firestore wrappers
| File | ~Lines | Responsibility |
|---|---|---|
| `attendance_service.dart` | 3990 | Core of the app: check-in/out, stats streams (today/weekly/monthly, per-manager/per-employee), QR token generation/validation, geofence checks, missed-checkout sync, absence detection, push-notification triggers. Largest file in the repo — read it in sections, not all at once. |
| `leave_service.dart` | 1660 | Leave request CRUD, approval workflow, leave-balance math |
| `notification_service.dart` | 1360 | FCM setup (foreground/background handlers), local notifications, in-app banners |
| `permission_service.dart` | 620 | "Permission to step out" requests (exit/return), distinct from leave |
| `geo_fence_service.dart` | 570 | Radius/distance math, office geofence config |
| `staff_service.dart` | 290 | Staff CRUD, registration, directory |
| `payroll_service.dart` | 200 | Salary/attendance-based payroll calculations |
| `anniversary_greeting_service.dart` | 190 | Work-anniversary greeting logic |
| `manager_account_service.dart` | 130 | Manager onboarding/account management |
| `attendance_log_service.dart` | 65 | Thin wrapper over `attendance_logs` |
| `white_label_service.dart` | 55 | Reads/writes tenant branding config |
| `email_service.dart` | 50 | Calls the Vercel `sendCredentialEmail` endpoint |
| `profile_photo_sync_service.dart` | 40 | Keeps cached profile photos in sync across collections |
| `qr_service.dart` | 0 | **Empty — dead file** |

### Models (`lib/models/`)
`Staff`, `AttendanceModel`, `AttendanceLog`, `LeaveRequest`, `PermissionRequest`, `ManagerModel`, `WhiteLabelModel`, `NotificationModel`. `CheckoutRequest`, `WeeklyAttendance`, `MonthlyAttendance`, and several private helper classes (`AttendanceSubmissionResult`, `AttendanceAlert`, etc.) are defined inline at the bottom of `attendance_service.dart` rather than under `lib/models/`.

### Vercel backend (`vercel_backend/api/`) — replaces the removed Cloud Functions
- `sendNotification.js` — FCM push for arbitrary recipients (phone/identifier/role). The Flutter app calls this via `NotificationService`. Contains the text-cleanup helpers (`cleanNotificationText`, `cleanNotificationTitle`) that strip legacy "TЯAKR •"/"TRAKA" brand prefixes and reword raw event text ("staff checked in" → "Secure Check-In", etc.).
- `notificationAction.js` — POST endpoint handling approve/reject actions taken from a push notification (ports the old `processNotificationAction` Firestore trigger + `handleLeaveAction`/`handlePermissionAction`/`handleCheckoutAction`).
- `sendCredentialEmail.js` — sends login credentials via nodemailer (requires `SMTP_EMAIL`/`SMTP_PASSWORD` env vars).
- `broadcastNotification.js` — platform-wide broadcast push used by the super-admin composer in `notifications_module.dart`.
- `qrNotifications.js` — cron, daily at 3 AM, rotates `qr_tokens` per tenant (90-day expiry window logic).
- `syncMissedCheckout.js` — cron (`*/15 * * * *`), scans the last 7 days of `attendance` for missing checkouts and pushes actionable approve requests to admins.
- `attendanceReminders.js` — cron (`*/15 * * * *`), sends check-in/check-out reminder pushes near configured cutoff times.
- `lib/helpers.js`, `lib/firebaseAdmin.js` — shared Firebase Admin init, token collection, FCM send, and cron-secret helpers.
- Cron jobs are declared in `vercel_backend/vercel.json`; each cron endpoint may require `CRON_SECRET`/`QR_CRON_SECRET`. Note: Vercel Hobby-plan crons run at most once per day — upgrade or self-host if the 15-minute cadence matters.

### Firestore collections
`staff`, `managers`, `admins`, `users`, `staff_metadata`, `attendance`, `attendance_alerts`, `attendance_logs`, `checkout_requests`, `leave_requests`, `permission_requests`, `notifications`, `notification_actions`, `event_dedupe`, `qr_tokens`, `geo_config`, `offices`, `app_config`, `settings`, plus per-tenant white-label config. (`employees` and `tenants` also appear in `firestore.rules`/old Cloud Functions but aren't written by the client — likely legacy or future multi-tenant scaffolding.)

### Firestore rules
`firestore.rules` requires `request.auth != null` (`signedIn()`) for read/write on every listed collection — there is **no role-based (admin/manager/staff) or ownership-based restriction**, so any authenticated user can read/write any document in any collection. Everything else is denied by the trailing catch-all. Treat this as a known gap: row-level authorization (e.g. staff can only write their own attendance doc) is the natural next hardening step before production multi-tenant use.

## Key Dependencies

- `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_messaging`, `google_sign_in`
- `provider` (state) — not Riverpod/Bloc
- `mobile_scanner` (scanning), `qr_flutter` (generation)
- `geolocator`, `permission_handler`, `flutter_map` + `latlong2` (office map picking)
- Reporting/export: `fl_chart`, `csv`, `excel`, `pdf`, `printing`, `file_saver`, `file_picker`
- `flutter_local_notifications`, `google_fonts` (Poppins is also bundled as a local font family), `cached_network_image`, `image_picker`, `intl`, `http`, `url_launcher`

## Notes for future changes

- `attendance_service.dart` is the highest-risk file to edit — it's nearly 4000 lines, with several streams keyed off manager-name/employee-id string matching (see `_teamEmployeeIdsStream`, `_addAlias`) rather than strict IDs. Grep for the specific `Stream`/`Future` method by name rather than reading the whole file.
- **No Cloud Storage anywhere** — the app targets the Firebase Spark plan (Auth + Firestore only, no Storage, no Cloud Functions at runtime). Logos (`CompanyLogoService`, `WhiteLabelService.uploadLogo`) and profile photos are stored as base64 `data:` URLs inside Firestore docs; never reintroduce `firebase_storage` or Storage bucket provisioning.
- The README states the geofence default as 100m in places; the actual default in code (`staff_scan_qr_screen.dart`) is **50m** — trust the code over the README on this point.
- No CI config, no Cursor/Copilot rule files, and no automated test suite currently exist in this repo.
