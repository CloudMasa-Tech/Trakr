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

# TRakr Multi-Tenant Architecture (Corrected)

## Core Principle

**One master project (Blaze) orchestrates many isolated tenant projects (Spark).**
The master project never stores tenant business data. Tenant projects never touch billing.

```
                    ┌─────────────────────────────┐
                    │   MASTER PROJECT (Blaze)     │
                    │   trakradminsetup-28437      │
                    │                               │
                    │  - Admin/onboarding UI        │
                    │  - Cloud Functions (control)  │
                    │  - Master Firestore           │
                    │    (workspaces, platformStats,│
                    │     users/superadmins,        │
                    │     activity_logs)             │
                    │  - Service Account w/          │
                    │    Project Creator role on     │
                    │    folders/818058604638        │
                    └───────────────┬───────────────┘
                                    │
                     creates & provisions via
                     Cloud Functions (idempotent)
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────┐          ┌───────────────┐          ┌───────────────┐
│ TENANT PROJECT │          │ TENANT PROJECT │          │ TENANT PROJECT │
│   (Spark)      │          │   (Spark)      │          │   (Spark)      │
│ company-A-xxxx │          │ company-B-xxxx │          │ company-C-xxxx │
│                │          │                │          │                │
│ - Firestore    │          │ - Firestore    │          │ - Firestore    │
│   (Native mode)│          │   (Native mode)│          │   (Native mode)│
│ - Email/Pass   │          │ - Email/Pass   │          │ - Email/Pass   │
│   Auth only    │          │   Auth only    │          │   Auth only    │
│ - Firestore    │          │ - Firestore    │          │ - Firestore    │
│   rules        │          │   rules        │          │   rules        │
│ - NO Storage   │          │ - NO Storage   │          │ - NO Storage   │
│ - NO Phone Auth│          │ - NO Phone Auth│          │ - NO Phone Auth│
│ - NO billing   │          │ - NO billing   │          │ - NO billing   │
│   linked       │          │   linked       │          │   linked       │
└───────────────┘          └───────────────┘          └───────────────┘
        all live under folders/818058604638
```

---

## 1. Master Project (Blaze — one time setup)

**Purpose:** control plane only. Orchestrates tenant lifecycle, never holds tenant business data.

| Component | Requirement |
|---|---|
| Pricing plan | **Blaze** (required — Cloud Functions need outbound network access to call CRM/Firebase Management APIs) |
| Billing account | One Google Cloud Billing Account, linked once |
| Service account | `Project Creator` role on `folders/818058604638`, plus Firebase Admin, Service Usage Admin, Firestore Admin scopes |
| APIs enabled | `cloudresourcemanager`, `firebase`, `firestore`, `identitytoolkit`, `serviceusage` |
| Firestore collections | `workspaces`, `platformStats/dashboard`, `activity_logs`, `users` (superadmins), `white_label_config` |
| Cloud Functions | `createTenantProject`, `deleteWorkspace`, `deployTenantRules` |

**Cost model:** you (CloudMaSa) pay only for the master project's Blaze usage — Cloud Functions invocations, CRM/Firebase Management API calls. This is small and predictable regardless of tenant count.

---

## 2. Tenant Projects (Spark — created per client, fully automated)

**Purpose:** isolated data + auth boundary per client company. No cost to you or them unless they exceed free quotas.

| Allowed on Spark (use these) | Blaze-only (avoid for tenants) |
|---|---|
| Firestore Native mode (free daily quota) | Cloud Storage / Firebase Storage buckets (blocked entirely on Spark since Sept 2024) |
| Email/Password Auth (up to 50K MAU free) | Phone Auth / SMS verification (Blaze-only since Sept 2024) |
| Firebase Hosting | Cloud Functions with outbound network calls to non-Google APIs |
| Analytics, Crashlytics, FCM | Any usage exceeding Spark's free daily/monthly quota |
| Firestore security rules deployment | — |

**Design constraint:** if TRakr ever needs tenant-side file uploads (e.g. attendance photos, documents), that single feature would force that tenant's project onto Blaze. Decide now whether to support it via a **shared bucket in the master project** instead (tenant data segmented by workspace ID, path-scoped security rules) — this keeps all tenant projects on Spark permanently.

---

## 3. Provisioning Flow (idempotent, state-aware)

```
User submits "Onboard new company" form
        │
        ▼
[Cloud Function: createTenantProject]
        │
        ├─ 1. generateUniqueProjectId(requestedId)
        │     ├─ candidate exists? check lifecycleState
        │     │    ├─ ACTIVE + under our folder → alreadyExisted=true, adopt it
        │     │    ├─ ACTIVE + different parent → collision, generate new suffix
        │     │    ├─ DELETE_REQUESTED / DELETE_IN_PROGRESS → collision
        │     │    │   (30-day grace period lock), generate new suffix
        │     │    └─ unknown state → treat as unusable, generate new suffix
        │     └─ no candidate exists → create fresh
        │
        ├─ 2. projects.create() [with retry+backoff on transient errors]
        ├─ 3. firebase.projects.addFirebase() [retry+backoff — GCP eventual consistency]
        ├─ 4. enable required APIs (Firestore, Identity Toolkit)
        ├─ 5. create Firestore Native DB [retry+backoff]
        ├─ 6. enable Email/Password Auth provider
        │
        │   NO billing account linkage step — tenant stays Spark
        │
        └─ return { alreadyExisted, firebaseEnabled, apisEnabled,
                     firestoreDbCreated, authEnabled, failedStep? }
        │
        ▼
[Flutter client: TenantProvisioner]
        │
        ├─ safely parse response (asStringKeyedMap — handles JS interop LinkedMap)
        ├─ if success or alreadyExisted → proceed
        ├─ if transient/retryable error → already retried server-side; surface real error only after exhaustion
        └─ continue to deployTenantRules → admin registration → onboardingStatus=ready
```

**Every step above must be retry-safe and idempotent** — re-running provisioning on a partially-completed workspace should pick up where it left off, not fail or duplicate resources.

---

## 4. Security Rules Boundary

- **Master Firestore rules:** gate all reads/writes behind `isSuperAdmin()`, checked via custom claims *or* `users/{uid}.role == 'super_admin'` doc. Applies to `companies`, `attendance`, `support_tickets`, `security_events`, `announcements`, `billing/invoices`, `billing/payments`, and any other platform-dashboard collection.
- **Tenant Firestore rules (`deployTenantRules`):** deployed independently per tenant project, scoped to that tenant's own admin/user accounts — completely separate rule set from the master project. Locked/default rules block tenant admins until this step succeeds.

---

## 5. Lifecycle / Cleanup

- `deleteWorkspace` must check project `lifecycleState` before attempting mutation — a project already `DELETE_REQUESTED` is in a 30-day Google-enforced lock; deletion function should detect this and clean up **Firestore workspace records only**, not attempt further GCP mutation.
- Never reuse a soft-deleted project ID until the 30-day window has passed (or use `gcloud projects undelete` within the window if recovery is needed).

---

## 6. What Requires Manual Setup (cannot be automated by Cloud Functions)

| Task | Why manual |
|---|---|
| Master billing account creation + linkage | One-time org-level GCP action |
| Master service account role grants | IAM policy changes typically done once via console/gcloud by an org admin |
| GCP folder (`818058604638`) creation | Org structure, done once |
| Quota increases (if tenant volume grows large) | Requires a Google support request |
| Waiting out 30-day soft-delete grace periods | Google-enforced, no API override |

Everything else — project creation, Firebase enablement, Firestore DB, Auth config, rules deployment — should be **fully automated and idempotent** per your current fixes.

---

## Summary of Your Goal vs. Reality

✅ **Achievable as designed:** master project on Blaze, every tenant project on Spark, using only Firestore Native + Email/Password Auth + Hosting.

⚠️ **Watch for:** any future feature requiring Cloud Storage or Phone Auth on tenant projects will force that tenant to Blaze. Plan around this now (e.g. centralize file storage in the master project) if you want to guarantee Spark-only tenants long-term.