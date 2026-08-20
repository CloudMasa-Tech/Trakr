# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**TЯAKR** (package name `attendqr`, README title "AttendQR Enterprise") — a multi-tenant, white-labelled Flutter QR/geofence attendance-management system with a Firebase backend (Auth, Firestore, Cloud Messaging, Cloud Functions). Targets Android, iOS, web, Windows, macOS, Linux.

## Common Development Commands

- **Install dependencies**: `flutter pub get`
- **Run the app (debug)**: `flutter run` (pass `-d chrome`, `-d windows`, `-d macos`, etc.)
- **Run tests**: `flutter test` — only the default `test/widget_test.dart` stub exists; there is no real test suite.
- **Static analysis / lint**: `flutter analyze`
- **Build Android APK**: `flutter build apk --release`
- **Build iOS app**: `flutter build ios --release`
- **Build web**: `flutter build web`
- **Regenerate launcher icons**: `flutter pub run flutter_launcher_icons` (config at the bottom of `pubspec.yaml`, source image `assets/trakr00-removebg-preview.png`)
- **Firebase Cloud Functions** (in `functions/`, TypeScript, Gen 2): deploy with `firebase deploy --only functions --project trakradminsetup-28437`. Runs on the **Blaze plan** — server-side tenant rules/index deployment, superadmin claim management. `SERVICE_ACCOUNT_JSON` secret in Secret Manager is used by functions to call Firebase Admin SDK on tenant projects.
- **Firestore rules/indexes**: `firebase deploy --only firestore:rules,firestore:indexes`
- **Deploy master rules**: `./deploy-master-rules.sh` (swaps in `firestore.rules.master`, deploys to `trakradminsetup-28437`, restores tenant rules)

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
5. The Cloud Function cron (via `qrNotifications` equivalent logic in scheduled functions) rotates per-tenant tokens in `qr_tokens` (90-day expiry window logic).

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
| `email_service.dart` | 50 | Sends credentials via email (uses Cloud Function if configured) |
| `profile_photo_sync_service.dart` | 40 | Keeps cached profile photos in sync across collections |
| `qr_service.dart` | 0 | **Empty — dead file** |

### Models (`lib/models/`)
`Staff`, `AttendanceModel`, `AttendanceLog`, `LeaveRequest`, `PermissionRequest`, `ManagerModel`, `WhiteLabelModel`, `NotificationModel`. `CheckoutRequest`, `WeeklyAttendance`, `MonthlyAttendance`, and several private helper classes (`AttendanceSubmissionResult`, `AttendanceAlert`, etc.) are defined inline at the bottom of `attendance_service.dart` rather than under `lib/models/`.

### Firebase Cloud Functions (`functions/src/`) — Gen 2, TypeScript
- `deployTenantRules` — Callable function. Deploys `firestore.rules` and `firestore.indexes.json` to a tenant project via Security Rules REST API + Firestore Admin REST API. Called by Flutter during tenant provisioning. Requires `super_admin` custom claim. Uses `SERVICE_ACCOUNT_JSON` secret from Secret Manager.
- `setSuperAdminClaim` — Callable function. Sets `super_admin: true` custom claim on a user in the master project. Only callable by existing superadmins. Enables Firestore rules to check `request.auth.token.super_admin == true` instead of Firestore read.
- `createTenantProject` — Callable function. Creates a new GCP/Firebase project under folder `818058604638` (tenant-projects) using Cloud Resource Manager API v3. Called by Flutter during tenant provisioning to automatically create the Firebase project. Requires `super_admin` custom claim. The created project automatically inherits IAM roles (`firebaserules.admin`, `datastore.indexAdmin`, `resourcemanager.projectCreator`) via folder-level IAM inheritance from the parent folder.
- Cron functions (Gen 2 scheduled) for `qrNotifications`, `syncMissedCheckout`, `attendanceReminders` — equivalent to former Vercel cron endpoints.
- `sendNotification`, `notificationAction`, `sendCredentialEmail`, `broadcastNotification` — migrated from former Vercel endpoints.

### Firestore collections
`staff`, `managers`, `admins`, `users`, `staff_metadata`, `attendance`, `attendance_alerts`, `attendance_logs`, `checkout_requests`, `leave_requests`, `permission_requests`, `notifications`, `notification_actions`, `event_dedupe`, `qr_tokens`, `geo_config`, `offices`, `app_config`, `settings`, plus per-tenant white-label config. (`employees` and `tenants` also appear in `firestore.rules`/old Cloud Functions but aren't written by the client — likely legacy or future multi-tenant scaffolding.)

### Firestore rules
`firestore.rules` requires `request.auth != null` (`signedIn()`) for read/write on every listed collection. The rules enforce tenant isolation and prevent privilege escalation:

- `isSuperAdmin()` — only the platform Super Admin (resolved via `users/{uid}.role == 'super_admin'` OR custom claim `super_admin == true`) has platform-wide authority.
- `inCompany(companyId)` — a signed-in user belongs to a company if they hold the `company_admin` `roleId` or are the Super Admin.
- `sameCompanyOnCreate()` / `sameCompany()` — writes/reads are scoped to the company owning the caller's `users.{uid}.companyId`.
- Privilege fields (`role/roleId/roleName/roleLevel/permissionIds`) may only be assigned by the Super Admin, a Company Admin, or the tenant's **seeded bootstrap admin** (verified via `app_config/admin_access` primaryAdminEmail match). Self-registered accounts must create their docs without any privilege fields (`noPrivilegeFields` guard), and may never change them on update (`unchangedPrivileges` guard).
- `app_config/admin_access` — the bootstrap trust anchor; only the platform Super Admin or the recorded primary admin may create/update it. The very first create is only allowed when no doc exists yet.

The catch-all `/{document=**}` denies all read/write. Row-level authorization is the natural next step before production multi-tenant use.

**Important**: On Spark plan, Firestore rules for each tenant project must be **manually deployed** via `firebase deploy --only firestore:rules` after the project is created and Email/Password auth is enabled. The client SDK cannot auto-deploy rules on Spark. **On Blaze, tenant rules are deployed automatically via `deployTenantRules` Cloud Function during provisioning.**

## Key Dependencies

- `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_messaging`, `google_sign_in`, `cloud_functions`
- `provider` (state) — not Riverpod/Bloc
- `mobile_scanner` (scanning), `qr_flutter` (generation)
- `geolocator`, `permission_handler`, `flutter_map` + `latlong2` (office map picking)
- Reporting/export: `fl_chart`, `csv`, `excel`, `pdf`, `printing`, `file_saver`, `file_picker`
- `flutter_local_notifications`, `google_fonts` (Poppins is also bundled as a local font family), `cached_network_image`, `image_picker`, `intl`, `http`, `url_launcher`

## Notes for future changes

- `attendance_service.dart` is the highest-risk file to edit — it's nearly 4000 lines, with several streams keyed off manager-name/employee-id string matching (see `_teamEmployeeIdsStream`, `_addAlias`) rather than strict IDs. Grep for the specific `Stream`/`Future` method by name rather than reading the whole file.
- **No Cloud Storage anywhere** — the app targets the Firebase Spark plan (Auth + Firestore only, no Storage, no Cloud Functions at runtime for tenant apps). Logos (`CompanyLogoService`, `WhiteLabelService.uploadLogo`) and profile photos are stored as base64 `data:` URLs inside Firestore docs; never reintroduce `firebase_storage` or Storage bucket provisioning.
- The README states the geofence default as 100m in places; the actual default in code (`staff_scan_qr_screen.dart`) is **50m** — trust the code over the README on this point.
- No CI config, no Cursor/Copilot rule files, and no automated test suite currently exist in this repo.
- **Tenant Firestore rules are now deployed automatically via Cloud Function `deployTenantRules` during provisioning** — no manual `firebase deploy` per tenant needed.
- **Superadmin custom claim** (`super_admin: true`) is the preferred authorization mechanism in Firestore rules (checked via `request.auth.token.super_admin`). The fallback email match in `app_config/admin_access` remains for initial bootstrap.