# Client-Side Architecture: Multi-Tenant Workspace Refactor

**App:** `attendqr` (Flutter 3.44.2 / Dart 3.12.2, Provider, Firebase)
**Scope:** This document is the CLIENT implementation plan only. Vercel serverless endpoints / Firestore rules / Storage rules changes are called out as coordination points, not designed here.
**Status:** Design v1

---

## 9. Phase 4 — Workspace Resolution (implemented)

> This section documents the **implemented** workspace-resolution flow that was
> added on top of Phases 2–3 (dynamic multi-project Firebase + Master control
> plane). It supersedes the earlier slug/URL-based design in §2–§8 for the
> *bootstrap* path only; the rest of that design is unaffected and deferred.

### 9.1 Goal and flow

Before any login is attempted the user (or the local cache) resolves **which
tenant workspace** the app should talk to. The tenant's Firebase project is
then activated and the existing auth/attendance/payroll code runs against it
unchanged.

```
1. User enters a workspace code            → WorkspaceCodeScreen
2. Read workspace details from Master      → WorkspaceResolverService (control plane)
3. Validate + retrieve Firebase config     → WorkspaceResolverService._validate / WorkspaceFirebaseConfig
4. Initialize FirebaseManager with creds   → TenantBootstrapService → FirebaseManager.initializeTenantApp
5. Set active FirebaseApp                  → FirebaseManager.activateApp → FirebaseContextProvider.setActive
6. Continue login on that tenant           → AppRoot (provider tree bound to the tenant FirebaseContext)
```

Restart with a previously connected workspace skips 1–3: the config is restored
from the local cache and steps 4–6 run automatically (auto-reconnect).

### 9.2 New files

| File | Responsibility |
|---|---|
| `lib/control_plane/services/workspace_resolver_service.dart` | `WorkspaceResolverService.resolve(code)` — normalizes the code, reads `workspaces/{id}` via `WorkspaceRegistryService.resolveByCode`, and validates (exists / config valid / status active). Throws typed `WorkspaceResolutionException` with a user-facing message. Never touches `FirebaseManager`. |
| `lib/control_plane/services/tenant_bootstrap_service.dart` | `TenantBootstrapService` — owns the tenant lifecycle: `bootstrap(workspace)` (init + activate + cache), `restoreLastWorkspace()` (offline auto-reconnect from `shared_preferences`), `clearLastWorkspace()` (dispose + forget). |
| `lib/providers/workspace_bootstrap_provider.dart` | `WorkspaceBootstrapProvider` — `ChangeNotifier` driving the flow with phases `bootstrapping → needsWorkspace → ready`; exposes `connect(code)`, `clear()`, the resolved `Workspace`, and the active `FirebaseContext`. |
| `lib/screens/auth/workspace_code_screen.dart` | Pre-auth gate UI (mirrors `LoginScreen` styling): code field, Continue button, inline error banner for invalid/unavailable workspaces. |
| `lib/main.dart` (restructured) | `WorkspaceGateApp` (bootstrap gate + root `FirebaseContextProvider`/`WorkspaceBootstrapProvider`) and `AppRoot` (the former `MyApp` provider tree, now bound to the tenant context). |

`WorkspaceFirebaseConfig` gained `bool get isValid` (non-empty `apiKey` /
`appId` / `projectId` / `messagingSenderId`), used to reject not-yet-provisioned
workspaces.

### 9.3 Caching and auto-reconnect

- Keys in `shared_preferences`: `workspace_cache_id`, `workspace_cache_json`.
- The JSON payload is a JSON-safe subset of `Workspace` (`toMap()` embeds
  Firestore `Timestamp`s which `jsonEncode` can't serialize, so dates are stored
  as ISO strings and degrade to `null` on restore — they aren't needed to
  reconnect).
- `restoreLastWorkspace()` reads only the cache (no network), so a cold start
  reconnects offline. On a corrupted/incomplete cache the provider clears it and
  falls back to the code-entry screen.
- The auth session cache (`auth_session_*`) is unchanged. Because the gate only
  asks for a code when **no** workspace is cached, the app is always reconnected
  to the same tenant the session belongs to; cross-workspace session leakage is
  structurally impossible until a "switch workspace" action is added (see 9.6).

### 9.4 Error handling (invalid workspace)

| Condition | `WorkspaceResolutionError` | Shown to user |
|---|---|---|
| Empty code | `empty` | "Please enter your workspace code." |
| No `workspaces` doc with that code | `notFound` | "We couldn't find a workspace with that code…" |
| Config incomplete | `notProvisioned` | "This workspace is not ready yet…" |
| Status `provisioning` | `provisioning` | "still being set up…" |
| Status `suspended` | `suspended` | "currently suspended…" |
| Status `decommissioned` | `decommissioned` | "no longer available." |
| Network / Firestore failure | `unexpected` | "couldn't reach the workspace directory…" |

The error is shown as an inline banner on `WorkspaceCodeScreen`; the user stays
on the form to retry.

### 9.5 Provider tree restructure

```
main()
 └─ runApp(WorkspaceGateApp(firebaseContext: defaultProjectContext))
     └─ MultiProvider
         ├─ FirebaseContextProvider(context: default)          ← root, updated live by setActive
         └─ WorkspaceBootstrapProvider                         ← restore/connect/clear
             └─ Consumer<WorkspaceBootstrapProvider>
                 ├─ bootstrapping → _WorkspaceBootstrapLoadingScreen
                 ├─ needsWorkspace → WorkspaceCodeScreen
                 └─ ready → AppRoot(firebaseContext: tenantContext)
                     └─ MultiProvider (WhiteLabelProvider / AuthSessionProvider / CompanyProvider)
                         └─ Consumer<WhiteLabelProvider> → MaterialApp (unchanged)
```

Why the tree is rebuilt on `ready`: `AuthSessionProvider`, `WhiteLabelProvider`
and `CompanyProvider` capture their `FirebaseContext` in a `final` field at
construction. Swapping `FirebaseContextProvider.setActive` alone updates the
static context, but those providers stay bound to the project they were born
with — so the app must re-create them once the tenant project is active. This is
also why the gate's loading/entry screens live under a separate small
`MaterialApp` (`_gateTheme`) instead of reusing the white-label-themed one.

### 9.6 Constraints and future work

- **Messaging stays on the default app** (`firebase_messaging` 15.x has no public
  `instanceFor`); auth/firestore/storage are per-app. Existing `NotificationService`
  re-binding via `FirebaseManager.setContextApplier` is unchanged.
- **One active workspace at a time; no "switch workspace" UI yet.** `clear()` /
  `clearLastWorkspace()` exist and are exercised by the restore-failure path; a
  user-facing "switch workspace" entry point is the natural next step (it will
  also need the auth-session cache scoped per workspace before switching is safe).
- **No auth/attendance/payroll changes were made.** `AppRoot` mounts the exact
  same provider set and screens as before; only the `FirebaseContext` they bind
  to is tenant-specific now.
- **Control plane reads stay on the Master project.** `WorkspaceRepository`
  anchors to `ControlPlaneFirebase.instance.context` (default app), so resolving
  a workspace never accidentally hits a tenant database.
- **Verification:** `flutter analyze` at the pre-existing 264-issue baseline
  (0 new), `flutter test` passes the stub, manual smoke of code-entry →
  login → restart auto-reconnect pending real tenant projects.

---

## 10. Phase 5 — Tenant Authentication (implemented)

> Phase 4 bound Firestore/storage/auth *instances* to the tenant project. Phase 5
> closes the last auth gaps so **every** authentication operation — login, logout,
> forgot-password, Google sign-in, and the account-creation side channels — runs
> against the tenant's Firebase project. No UI or flow changes; identical behavior.

### 10.1 Audit result: already tenant-correct

| Concern | Status |
|---|---|
| `AuthSessionProvider` (`lib/providers/auth_session_provider.dart`) | All auth ops (`signIn`, `signInWithGoogle`, `sendPasswordResetEmail`, `signOut`, `register`, role resolution) go through `_auth` → `FirebaseContext.auth` → `FirebaseAuth.instanceFor(app: tenantApp)`. Already correct — no edits needed. |
| `FirebaseContext.fromApp` (`lib/firebase/firebase_context.dart:56`) | Derives `auth`, `firestore`, `storage` via `instanceFor(app:)`. Already correct. |
| `StaffService.addStaff` (`lib/services/staff_service.dart:24-29`) | Secondary "StaffCreation_*" app uses `_context.app.options` (tenant config) + `instanceFor`. Already correct — the temporary account is created in the tenant project, then the app is deleted. |
| `ManagerAccountService` (`lib/services/manager_account_service.dart:54,150`) | Both "ManagerCreation_*" / "CompanyAdminCreation_*" secondary apps already pass `_context.app.options`. Already correct. |
| `FirebaseManager.getAuth` (`lib/firebase/firebase_manager.dart:210`) | `instanceFor(app: getTenantApp(...))`. Already correct. |

`company_admins_module.dart` / `users_module.dart` "password reset" calls are
`DocumentReference` methods (Firestore), not Firebase Auth — unrelated, unchanged.

### 10.2 The one real change: tenant web persistence

`main.dart:37-40` set `Persistence.LOCAL` and Firestore long-polling on the
**default** app only. Now that login runs on the tenant app, the same web-only
settings are applied to each tenant app at creation time in
`FirebaseManager.initializeTenantApp` (`lib/firebase/firebase_manager.dart`):

```dart
if (kIsWeb) {
  await FirebaseAuth.instanceFor(app: app).setPersistence(Persistence.LOCAL);
  FirebaseFirestore.instanceFor(app: app).settings = const Settings(
    webExperimentalForceLongPolling: true,
  );
}
```

Why this location: `initializeTenantApp` is `await`ed by
`TenantBootstrapService.bootstrap` / `restoreLastWorkspace` **before**
`AppRoot` constructs `AuthSessionProvider`, so persistence is guaranteed set
before the first `currentUser` read / `idTokenChanges()` listener. It also runs
once per tenant app (idempotent via the app cache), including on auto-reconnect
after a cold start.

Out of scope (unchanged): the default-app persistence/long-polling block in
`main.dart` (serves the Master control-plane gate) and the default-app messaging
initializations in `notification_service.dart:27,643` (messaging is pinned to the
default project per §9.6).

### 10.3 Verification

- `flutter analyze` → still 264 issues (0 new).
- `flutter test` → stub passes.
- Manual: web build → enter code → login → restart reconnects same tenant and
  the session persists via IndexedDB (tenant-scoped persistence key).

---


## 0. Verified starting state (facts the design is built on)

| Fact | Source |
|---|---|
| No go_router; `MaterialApp` with `home:` + 4 dead named routes | `lib/main.dart:80-85` |
| `AnimatedLaunchScreen` (3.6s) hard-`pushReplacement`s to `AuthGateScreen` | `lib/main.dart:113-121` |
| Roles: `superAdmin / companyAdmin / user`; role resolved from global `users/{uid}` + directory fallback, cached in `shared_preferences` | `lib/providers/auth_session_provider.dart` |
| `signIn()` blocks on role resolution; throws on no role | `auth_session_provider.dart:645-664` |
| `CompanyProvider` constructed but never consumed | `lib/providers/company_provider.dart` |
| `Company` model has **no** `workspaceSlug` | `lib/models/company.dart` |
| `CompanyService.onboardCompany()` → `companies/{autoId}` + global `admins`/`users` admin account | `lib/services/company_service.dart` |
| `WhiteLabelProvider` self-listens to global `settings/white_label` at construction | `lib/providers/white_label_provider.dart:24-32` |
| `NotificationService` is a singleton constructed in `main()` before `runApp` | `lib/services/notification_service.dart:39-43`, `lib/main.dart:37` |
| `attendance_service.dart` = 3990 lines; deterministic ids `attendance_{safeId}_{dateKey}`; `qr_tokens/{tenantId}` where tenantId = admin **auth uid** | `attendance_service.dart:2276`, `1905-1966` |
| ~394 `collection(` call sites, 43 files, all on global top-level collections | grep |
| No `pushNamed` anywhere (only 11 imperative nav sites; the rest are fine with a nested navigator) | grep |
| `firestore.rules` `match /companies/{companyId}` — single doc, **no recursive wildcard**, so subcollections are currently denied | `firestore.rules:69-71` |
| `firebase.json` hosting has `rewrite ** → /index.html` (good for PathUrlStrategy) | `firebase.json` |
| All platforms point at the single production project `trakradminsetup-28437` | `lib/firebase_options.dart:43-51` |
| No test suite (only `test/widget_test.dart` stub); verification = `flutter analyze` + manual smoke | CLAUDE.md |

---

## 1. Dependencies

Add exactly two things to `pubspec.yaml`:

| Package | Version | Purpose |
|---|---|---|
| `go_router` | `^16.0.0` | Declarative, URL-driven routing with sync `redirect:` support and `StatefulShellRoute`. Dart 3.12.2 / Flutter 3.44.2 satisfies its SDK floor (`>=3.6.0`). Uses the BuildContext API (`GoRouter.of`, `context.go`). |
| `flutter_web_plugins` | `sdk: flutter` | `usePathUrlStrategy()` (from `package:flutter_web_plugins/url_strategy.dart`) so URLs are `/green-hospital/dashboard` not `#/green-hospital/dashboard`. SDK-bundled; no version constraint. |

Do **not** add `uuid` (Firestore auto-ids + the `slugs/{slug}` reservation doc cover uniqueness), `url_strategy` package (superseded by the SDK export), or `equatable` (keep it simple).

---

## 2. New files under `lib/workspace/`

### 2.1 `lib/workspace/utils/slugify.dart`

```dart
String slugify(String name);                       // lower, ASCII-only, spaces->'-', strip non [a-z0-9-]
String slugifyWithRandomSuffix(String base, int n); // "$base-$n"
```

Rules: trim → lowercase → NFC-normalize → transliterate common accents → collapse runs of non `[a-z0-9]` into single `-` → trim leading/trailing `-` → enforce max 40 chars. Empty result → fallback `"workspace"`.

### 2.2 `lib/workspace/models/workspace.dart`

```dart
class Workspace {
  final String companyId;
  final String workspaceSlug;
  final String companyName;
  final String? logoUrl;
  final String plan;                 // Free | Pro | Enterprise (map to subscriptionPlan on write)
  final String subscriptionStatus;   // active | trialing | past_due | canceled
  final bool isActive;
  final String? primaryColorHex;
  final String? supportEmail;
  final Map<String, dynamic> settings; // timezone, locale, featureFlags, defaultRadiusMeters…

  const Workspace({...});
  factory Workspace.fromCompany(Company company);
  factory Workspace.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc);
  Map<String, dynamic> toMap();      // mirrors on-disk shape: companyName, workspaceSlug, plan…
  Workspace copyWith({...});
}
```

`fromCompany()` derives everything from the existing `companies/{companyId}` doc (it already carries `name`, `logoUrl`, `primaryColorHex`, `supportEmail`, `plan`, `subscriptionStatus`, `isActive`). The **`companies/{companyId}` doc remains the single source of truth** — we add `workspaceSlug` to it at onboarding and stop at that. `settings` is read from the `companies/{companyId}/settings` subcollection via `CompanyRepository` (see 2.4); `Workspace.settings` is the merged cache, not a separate doc.

### 2.3 `lib/workspace/services/workspace_service.dart`

```dart
class WorkspaceService {
  Future<Workspace?> resolveBySlug(String slug);          // companies.where('workspaceSlug', isEqualTo: slug).limit(1)
  Future<Workspace?> resolveById(String companyId);       // companies/{companyId}
  Stream<Workspace?> streamWorkspace(String companyId);   // live branding/subscription updates
  Future<bool> isSlugAvailable(String slug);              // reads slugs/{slug}
  Future<String> generateUniqueSlug(String companyName);  // slugify + reserve + vary on collision
  Future<void> reserveSlug(String slug, {required String companyId}); // writes slugs/{slug} = {companyId}
}
```

Uniqueness: `slugs/{workspaceSlug}` is a **reservation doc** (`{companyId, createdAt}`). `generateUniqueSlug` loops `slug`, `slug-1`, `slug-2`… calling `isSlugAvailable` (a `get` on `slugs/{candidate}`). The write of the reservation + the `companies/{companyId}` doc happens inside one **Firestore batch** in onboarding, which makes the collision window a fail-soft retry rather than a data corruption. Because doc-id equality on `slugs/{slug}` is atomic in Firestore, two concurrent onboarders can't both win the same slug. Also write `workspaceSlug` onto the company doc and into `users/{adminUid}.workspaceSlug`.

### 2.4 `lib/workspace/services/company_repository.dart`

```dart
class CompanyRepository {
  // companies/{companyId}/companyInfo
  Future<CompanyProfile?> readProfile(String companyId);
  Stream<CompanyProfile?> streamProfile(String companyId);
  Future<void> updateProfile(String companyId, Map<String, dynamic> updates);
  // companies/{companyId}/settings   (operational: timezone, locale, featureFlags, radius…)
  Future<Map<String, dynamic>> readSettings(String companyId);
  Stream<Map<String, dynamic>> streamSettings(String companyId);
  Future<void> updateSetting(String companyId, String key, dynamic value);
  // companies/{companyId}/subscription
  Future<SubscriptionInfo?> readSubscription(String companyId);
  Stream<SubscriptionInfo?> streamSubscription(String companyId);
  Future<void> updateSubscription(String companyId, Map<String, dynamic> updates);
}
```

`CompanyProfile` / `SubscriptionInfo` live in `lib/workspace/models/` (small immutable models). The existing `Company` model stays for the super-admin portal and onboarding; `Workspace.fromCompany` bridges them.

### 2.5 `lib/workspace/services/workspace_scope.dart` — the plumbing decision

**Decision: a global mutable holder, not constructor injection.** Justification:

- There are 394 `collection(` call sites across 43 files and services are instantiated ad-hoc everywhere (`AttendanceService()` appears in dozens of widgets). Constructor injection means threading `companyId` through every service constructor **and** every instantiation site — the same blast radius we're trying to eliminate, plus hundreds of compile breakages in 113 files.
- The codebase already treats globals as the norm (`FirebaseAuth.instance`, `FirebaseFirestore.instance`, singleton `NotificationService`). A scoped holder is the same shape, set once at startup.
- It keeps `FirestorePaths` usable without `BuildContext`, satisfying the hard constraint that services construct Firestore directly.
- It's testable: `WorkspaceScope.withCompany(companyId: 'x', () { ... })` makes any service deterministic under test.

```dart
class WorkspaceScope {
  static WorkspaceScope get instance;               // singleton holder
  String? get companyId;
  String? get workspaceSlug;
  bool get isBound;
  String requireCompanyId();                        // throws StateError('no workspace bound') — fail loud
  String requireWorkspaceSlug();
  void bind({required String companyId, required String workspaceSlug});
  void clear();                                     // on signOut / workspace switch
  static T withCompany<T>({required String companyId, String? workspaceSlug, required T Function() body});
}
```

`WorkspaceProvider.loadBySlug/loadById` calls `bind()` when the workspace resolves and `clear()` on `clear()`/sign-out. Any Phase-2 service that fires before a workspace loads throws immediately — turning silent cross-tenant reads into startup errors.

### 2.6 `lib/workspace/services/firestore_paths.dart` and `lib/workspace/services/storage_paths.dart`

```dart
class FirestorePaths {
  // Pure builders — no global access; unit-testable.
  static String company(String companyId)            => 'companies/$companyId';
  static String sub(String companyId, String name)   => 'companies/$companyId/$name';
  static String companyInfo(String c)                => sub(c, 'companyInfo');
  static String users(String c)                      => sub(c, 'users');
  static String branches(String c)                   => sub(c, 'branches');
  static String attendance(String c)                 => sub(c, 'attendance');
  static String attendanceLogs(String c)             => sub(c, 'attendance_logs');
  static String attendanceAlerts(String c)           => sub(c, 'attendance_alerts');
  static String leaveRequests(String c)              => sub(c, 'leaveRequests');
  static String permissionRequests(String c)         => sub(c, 'permission_requests');
  static String checkoutRequests(String c)           => sub(c, 'checkout_requests');
  static String payroll(String c)                    => sub(c, 'payroll');
  static String announcements(String c)              => sub(c, 'announcements');
  static String shifts(String c)                     => sub(c, 'shifts');
  static String holidays(String c)                   => sub(c, 'holidays');
  static String settings(String c)                   => sub(c, 'settings');
  static String subscription(String c)               => sub(c, 'subscription');
  static String assets(String c)                     => sub(c, 'assets');
  static String reports(String c)                    => sub(c, 'reports');
  static String notifications(String c)              => sub(c, 'notifications');
  static String staff(String c)                      => sub(c, 'staff');
  static String managers(String c)                   => sub(c, 'managers');
  static String admins(String c)                     => sub(c, 'admins');
  static String qrTokens(String c)                   => sub(c, 'qr_tokens');
  static String geoConfig(String c)                  => sub(c, 'geo_config');
  static String offices(String c)                    => sub(c, 'offices');
  static String notificationActions(String c)        => sub(c, 'notification_actions');
  static String eventDedupe(String c)                => sub(c, 'event_dedupe');
  static String staffMetadata(String c)              => sub(c, 'staff_metadata');

  // Global-by-design (auth identity / platform telemetry) — deliberately NOT scoped:
  static const String globalUsers        = 'users';          // users/{uid} identity index
  static const String globalCompanies    = 'companies';      // registry + workspaceSlug lookup
  static const String globalSettings     = 'settings';       // settings/white_label platform default
  static const String globalAppConfig    = 'app_config';     // admin_access bootstrap
  static const String globalPlatform     = 'platformStats';  // super-admin platform analytics
  static const String globalActivity     = 'activity_logs';
  static const String globalAudit        = 'audit_logs';
  static const String globalSecurity     = 'security_events';
  static const String globalSupport      = 'support_tickets';
  static const String globalBilling      = 'billing';        // billing/invoices, billing/payments
  static const String globalAnnouncements= 'announcements';  // platform-wide announcements only
}
```

```dart
class StoragePaths {
  static String companyRoot(String workspaceSlug)       => 'companies/$workspaceSlug';
  static String companyLogo(String workspaceSlug)       => 'companies/$workspaceSlug/company-logo/logo.png';
  static String whiteLabel(String workspaceSlug)        => 'companies/$workspaceSlug/white-label/logo.png';
  static String profileImage(String slug, String uid)   => 'companies/$slug/profile-images/$uid/profile.png';
  static String employeeDocument(String slug, String empId, String name) => 'companies/$slug/employee-documents/$empId/$name';
  static String payroll(String slug, String periodKey)  => 'companies/$slug/payroll/$periodKey.pdf';
  static String report(String slug, String name)        => 'companies/$slug/reports/$name';
  static String branchAsset(String slug, String branchId, String name) => 'companies/$slug/branch-assets/$branchId/$name';
}
```

`CompanyLogoService.logoPath(companyId)` and `WhiteLabelService.uploadLogo` (`white_label/logo.png`) migrate to `StoragePaths.*` in Phase 2.

### 2.7 `lib/workspace/providers/workspace_provider.dart`

```dart
enum WorkspaceStatus { initializing, ready, notFound, error, denied }

class WorkspaceProvider extends ChangeNotifier {
  final WorkspaceService _workspaceService;
  WorkspaceStatus get status;
  Workspace? get workspace;
  String? get companyId;
  String? get workspaceSlug;
  String? get errorMessage;

  Future<void> loadBySlug(String slug);     // resolveBySlug → bind scope → streamWorkspace
  Future<void> loadById(String companyId);  // used by super-admin "open workspace" + deep links
  Future<void> loadFromInitialLocation();   // reads Uri.base on web, else '/' (native)
  void clear();                             // cancels stream, clears WorkspaceScope
  // statuses: notFound (slug didn't resolve), error (network), denied (auth mismatch, set by gate)
}
```

`loadBySlug`:
1. `status = initializing; notifyListeners();`
2. `workspace = await resolveBySlug(slug)` → `null` ⇒ `status = notFound`.
3. `WorkspaceScope.instance.bind(companyId, slug)`.
4. Subscribe `streamWorkspace(companyId)` for live branding/subscription/settings; re-`notifyListeners` per event. Workspace is **lazy-started in `main()` from `Uri.base`**, so deep links like `/green-hospital/dashboard` have their workspace mid-flight before the first frame.

### 2.8 `lib/workspace/services/navigation_service.dart`

```dart
class NavigationService {
  // URL helpers (pure strings — no context)
  static String workspaceRoot(String slug)   => '/$slug';
  static String login(String slug)           => '/$slug/login';
  static String forgotPassword(String slug)  => '/$slug/forgot-password';
  static String dashboard(String slug)       => '/$slug/dashboard';
  static String employees(String slug)       => '/$slug/employees';
  static String attendance(String slug)      => '/$slug/attendance';
  static String settings(String slug)        => '/$slug/settings';
  static String page(String slug, String segment) => '/$slug/$segment';

  // Runtime helpers
  static void go(BuildContext context, String path)     => context.go(path);
  static void push(BuildContext context, String path)   => context.push(path);
  static void pop(BuildContext context)                 => context.pop();
  static void goToLogin(BuildContext context);          // resolves current slug from WorkspaceProvider
  static void goToDashboard(BuildContext context);
  static void goToWorkspaceRoot(BuildContext context);
}
```

### 2.9 `lib/workspace/widgets/workspace_gate.dart`

Route shell for every `/{workspaceSlug}/…` page. Responsibilities, in order:

1. Read `workspaceSlug` from route params. If `WorkspaceProvider.workspaceSlug != param` (deep link / workspace switch), kick `loadBySlug(param)` from `initState` (idempotent if already loaded).
2. Render by status:
   - `initializing` → `WorkspaceLoadingScreen`
   - `notFound` → `WorkspaceNotFoundScreen(slug)`
   - `error` → `WorkspaceLoadingScreen(errorMessage, retry: () => loadBySlug(slug))`
   - `ready` → **membership check** (below) → `child` (the page builder) or `AccessDeniedScreen`.
3. **Membership verification** (defense in depth, on every workspace page):
   - `auth.user == null` → redirect to login (router handles; gate renders loading in the meantime).
   - `auth.companyId != null && auth.companyId != workspace.companyId` → `AccessDeniedScreen` (offer "Switch workspace / sign out", never auto sign-out — the user may be legitimately signed into another workspace in the same session).
   - superAdmin (`role == superAdmin`) visiting a `/{slug}/…` page → redirect to `/admin` (platform is not a workspace member).

```dart
class WorkspaceGate extends StatelessWidget {
  final Widget Function(BuildContext context) pageBuilder;
  const WorkspaceGate({super.key, required this.pageBuilder});
}
```

### 2.10 Workspace screens

- `lib/workspace/screens/workspace_loading_screen.dart` — dark splash-styled loader (reuses the `AnimatedLaunchScreen` color/look as a static frame) with the resolved `companyName`/logo.
- `lib/workspace/screens/workspace_not_found_screen.dart` — professional 404: slug, company name hint, "This workspace doesn't exist or is unavailable", CTA to contact support / go to landing.
- `lib/workspace/screens/access_denied_screen.dart` — "You don't have access to this workspace" + sign out button.

### 2.11 `lib/workspace/router/app_router.dart`

The `GoRouter` factory. Full tree in section 3. Owns `redirect:` logic that reads `AuthSessionProvider` + `WorkspaceProvider` via `Provider.of(…, listen: false)`.

---

## 3. go_router route tree

### 3.1 Route table

```
GoRouter(
  initialLocation: AppRouter.initialLocation(),   // Uri.base.path on web, '/' on native
  redirect: _globalRedirect,                      // auth + role short-circuits (see 3.3)
  routes: [
    // ── Platform (no workspace) ─────────────────────────────
    GoRoute(path: '/', builder: (_) => LandingPage()),        // web marketing
    GoRoute(
      path: '/admin',
      redirect: _superAdminOnly,                             // !superAdmin → '/'
      builder: (_, __) => SuperAdminPortalScreen(onLogout: ...),
    ),
    // ── Workspace shell (single branch, all pages under it) ─
    GoRoute(
      path: '/:workspaceSlug',
      builder: (_, state) => WorkspaceGate(
        pageBuilder: (_) => const WorkspaceRootRedirect(),   // picks dashboard/login by auth state
      ),
      routes: [
        GoRoute(path: 'login',          builder: (_, s) => LoginScreen(workspaceSlug: s.pathParameters['workspaceSlug'])),
        GoRoute(path: 'forgot-password',builder: (_, s) => ForgotPasswordScreen(workspaceSlug: ...)),
        GoRoute(path: 'dashboard',      builder: (_, s) => WorkspaceGate(pageBuilder: (_) => dashboardForRole())),
        GoRoute(path: 'employees',      builder: (_, s) => WorkspaceGate(pageBuilder: (_) => AppShell(initialIndex: employeesTabIndex))),
        GoRoute(path: 'attendance',     builder: (_, s) => WorkspaceGate(pageBuilder: (_) => AppShell(initialIndex: attendanceTabIndex))),
        GoRoute(path: 'settings',       builder: (_, s) => WorkspaceGate(pageBuilder: (_) => AppShell(initialIndex: settingsTabIndex))),
        GoRoute(path: 'not-found',      builder: (_, __) => WorkspaceNotFoundScreen()),
        // catch-all INSIDE the workspace — anything unresolved under a slug tries slug resolution first
        GoRoute(path: 'x:path(.*)',     builder: (_, s) => WorkspaceGate(pageBuilder: (_) => const UnknownPage())),
      ],
    ),
    // ── Global catch-all ─────────────────────────────────────
    GoRoute(path: '/:catchAll(.*)', builder: (_, __) => const NotFoundScreen()),
  ],
)
```

### 3.2 What happens to the existing pieces

| Today | New role |
|---|---|
| `AnimatedLaunchScreen` | **Removed from the startup path.** Its 3.6s timed animation + `pushReplacement` cannot coexist with URL-driven startup (a deep link must land immediately). Its visual identity is reused by `WorkspaceLoadingScreen`. File can stay for the brand, but `main.dart` no longer references it. |
| `AuthGateScreen` | **Removed as a widget from the tree.** Its dispatch logic is split: (a) role dispatch → `dashboardForRole()` builder, (b) unauth redirect → `_globalRedirect`, (c) loading screen → `WorkspaceLoadingScreen`. Keep the file briefly as a pure-function host for `dashboardForRole()` during Phase 1, then delete. |
| `LoginScreen` | Gains `workspaceSlug` param; its post-login `pushAndRemoveUntil(AuthGateScreen)` (`login_screen.dart:75`) becomes `context.go(NavigationService.dashboard(slug))`. |
| `ForgotPasswordScreen` | Gains `workspaceSlug`; route `/{slug}/forgot-password`; its `pushReplacement` (`forgot_password_screen.dart:169`) becomes `context.go`. |
| `LandingPage` | Stays at `/` (web, unauth). Its `_goToLogin` no longer pushes a bare `LoginScreen` — the CTA collects a slug or navigates to a `/workspace` finder; "never leave the workspace" applies once inside a slug. |
| `SuperAdminPortalScreen` | Stays global at `/admin`. Super admins are platform-level; they are never routed under a slug. |
| `AppShell` | Rendered by page routes with a fixed `initialIndex` (dashboard/employees/attendance/settings → tab indexes 0/N/M/K). Internal `setState` tab switching **does not rewrite the URL** in Phase 1 (see 3.4). |
| `EmployeeHomeScreen` | Rendered at `/{slug}/dashboard` for `AppUserRole.user`. |
| `routes:` map + `AppFooter` | Dead routes removed; `AppFooter` keeps wrapping the `builder:` in `MaterialApp.router`. |

### 3.3 Redirect rules (executed in this order in `_globalRedirect`)

1. **Workspace not resolved yet** (`WorkspaceProvider.status == initializing` and slug param present) → return `null` (stay; `WorkspaceGate` shows loading).
2. **SuperAdmin** → allow `/admin` only; any `/{slug}/…` → `'/admin'`; `/` for a signed-in superAdmin → `'/admin'`.
3. **Unauthenticated** (`auth.user == null`, not loading):
   - `/` → allow (landing).
   - any `/{slug}/…` → `'/$slug/login'`.
   - `/login`, `/forgot-password` already contain the slug; allow.
4. **Authenticated but role still resolving** (`auth.isLoading`) → `null` (loading screen).
5. **Authenticated + role resolved**:
   - `/` → `'/${workspaceSlug}/dashboard'` (use cached slug from `AuthSessionProvider`/`WorkspaceProvider`).
   - `/{slug}/login` or `/{slug}/forgot-password` → `'/$slug/dashboard'` (already signed in).
   - `/{slug}/dashboard` for `user` → `EmployeeHomeScreen`; for `companyAdmin` → `AppShell(initialIndex: 0)`.
6. **Wrong role for page** — employees/attendance/settings under a `user` session → redirect to `/{slug}/dashboard`.

`WorkspaceGate` is the **second** enforcement layer (async membership check). Redirects are sync; the gate is where async slug resolution + `companyId` matching live. Both run; the gate is authoritative for "user belongs to this company".

### 3.4 Deep-link resolution and the AppShell index-navigation question

**Deep link** (`/green-hospital/dashboard`): go_router matches the `/:workspaceSlug` branch synchronously (`workspaceSlug=green-hospital`). Builders must not block, so the branch builder returns `WorkspaceGate`, whose `initState` calls `loadBySlug('green-hospital')`. Because `main()` already kicked `loadFromInitialLocation()` with the same URL, the workspace is typically already `ready` by first frame. This "route → gate → provider load → page" is the standard pattern and is the only async-safe shape in go_router.

**AppShell / EmployeeHomeScreen vs routes — decisive recommendation:** keep both files **untouched as stateful index shells** for Phase 1. Each workspace page route renders the correct shell with the matching `initialIndex`. Consequences, accepted explicitly:

- In-app tab switching (internal `setState`) keeps the URL on the last-visited page (e.g. user lands on `/dashboard`, taps to the "Reports" tab, URL still says `/dashboard`). Deep links always land on the right tab; URL/tab sync is only lossy after manual tabbing.
- Tab state is preserved across manual tabbing (shell instance lives) but **lost on URL-driven navigation** (new route ⇒ new shell instance ⇒ `initState` re-runs, streams re-subscribe).

This is the pragmatic 80/20: converting two 1500/6000-line shells into `StatefulShellRoute.indexedStack` branches is a Phase-2.5 optional refactor with real regression risk and no user-visible win in Phase 1. If/where we do it, `AppShell(initialIndex: k)` becomes `StatefulShellRoute.indexedStack` with one `StatefulShellBranch` per tab, `initialIndex: k` → `state.uri` matching, and the internal index becomes a `context.go` call. Documented, deferred.

---

## 4. Bootstrap flow in `lib/main.dart`

New sequence, exactly:

```
main()
 ├─ WidgetsFlutterBinding.ensureInitialized();
 ├─ if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
 ├─ [web] FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
 ├─ [web] FirebaseFirestore.instance.settings = Settings(webExperimentalForceLongPolling: true);
 ├─ [web] usePathUrlStrategy();                                   // flutter_web_plugins; before runApp
 ├─ assert web project id: if (kIsWeb && Firebase.app().options.projectId != 'trakradminsetup-28437')
 │       debugPrint(URGENT MESSAGE: firebase_options.web is stale — see Risks §8.6);
 ├─ unawaited(NotificationService().initialize());                // unchanged; token writes stay global
 ├─ final appRouter = AppRouter.build();                          // initialLocation from Uri.base
 ├─ runApp(MultiProvider(
 │     providers: [
 │       ChangeNotifierProvider(create: (_) => AuthSessionProvider()),                       // unchanged
 │       ChangeNotifierProvider(create: (_) => WorkspaceProvider()..loadFromInitialLocation()),
 │       ChangeNotifierProvider(create: (_) => WhiteLabelProvider()),                        // workspace-aware now
 │     ],
 │     child: Consumer<WhiteLabelProvider>(
 │       builder: (_, whiteLabel, __) => MaterialApp.router(
 │         routerConfig: appRouter,
 │         theme: whiteLabel.lightTheme,
 │         darkTheme: whiteLabel.darkTheme,
 │         themeMode: ThemeMode.light,
 │         builder: (context, child) => AppFooter wrapper (unchanged),
 │       ),
 │     ),
 │   ));
```

Key decisions:

- **`CompanyProvider` is deleted** (`lib/providers/company_provider.dart`). It's dead today; its two jobs (read `users/{uid}.companyId`, stream `companies/{id}`) are superseded by `AuthSessionProvider.companyId` + `WorkspaceProvider.streamWorkspace`. Remove the provider entry in `main.dart` and the import.
- **`WhiteLabelProvider` becomes workspace-driven** (this is the cleanest option, and the reason is data shape): the `companies/{companyId}` doc **already carries `primaryColorHex`, `logoUrl`, `supportEmail`**, so per-tenant branding needs **no new document** — the workspace stream (already live for subscription/settings) is the branding feed. Recommendation:
  - Keep `settings/white_label` **only as the platform default** (fallback palette/logo when no workspace is bound — i.e. landing, login pre-resolution, not-found).
  - `WhiteLabelProvider` stops self-listening in `create()`. It now watches `WorkspaceProvider`; on `ready` it (a) derives `WhiteLabelModel` from `workspace.primaryColorHex/logoUrl/supportEmail`, (b) keeps the platform default stream as the underlay, (c) does **not** start a second Firestore stream — `buildTheme` consumes the merged model.
  - The `white_label_screen` editor writes branding fields to `companies/{companyId}` (Phase 2); the global `settings/white_label` doc remains editable only by super-admin (platform default).

---

## 5. Auth integration

**Architecture decision: `users/{uid}` stays the global identity index for the life of the app.** It is the only thing that can bootstrap role + company before a workspace is resolved, it powers role resolution and the cached fast-restart path, and it's tiny (one doc read). Business data moves under `companies/{companyId}/…`; identity does not.

### 5.1 Additions to `AuthSessionProvider` (`lib/providers/auth_session_provider.dart`)

```dart
String? get companyId;        // from users/{uid}.companyId (cached alongside role)
String? get workspaceSlug;    // NEW field users/{uid}.workspaceSlug, written at onboarding/register/login
bool get belongsToWorkspace(String companyId) =>
    companyId != null && this.companyId == companyId;
```

- In `_loadRole` (`:387`), after resolving the role, also read `companyId` + `workspaceSlug` from the same `users/{uid}` doc and store them.
- Extend the shared_preferences cache: `auth_session_companyId_$uid` and `auth_session_workspaceSlug_$uid`, written in `_saveActiveSession`/`_cacheRole`, read in the cached-role fast path (`:158-170`) so a cold start does **not** need a network read to do the membership check. Admins still revalidate from Firestore as today.
- `register()` (`:592`) and Google sign-in (`:744`) already write `users/{uid}`; add `workspaceSlug` alongside `companyId`.
- `signIn()` signature: `signIn({required String email, required String password, String? workspaceSlug, String? companyId})`. Login screen passes the current route slug.
- Add a `_friendlyMessage` case for the new cross-workspace error.

### 5.2 Where membership is enforced — both layers

| Layer | When | What |
|---|---|---|
| **`AuthSessionProvider.signIn()`** (fail-fast) | At login submit | After role resolves, load the company for the requested slug (`WorkspaceService.resolveBySlug`). If `resolved.companyId != users.companyId` → **`signOut()`, throw** `Exception('This account doesn't belong to $companyName. Sign in with your workspace account.')`. Same check in `signInWithGoogle`. |
| **`WorkspaceGate`** (defense in depth) | Every `/{slug}/…` page render, including deep links and already-authenticated sessions | If `auth.companyId != workspace.companyId` → `AccessDeniedScreen`. If `auth.workspaceSlug` exists and mismatches the route slug → treat as denied. |

Rationale for both: `signIn()` gives the user an immediate, actionable error at the login form; `WorkspaceGate` covers every other entry (deep link into a workspace while signed in to another, session restored from cache, token refresh races). Neither auto-signs-out inside the gate — the user may hold sessions in multiple workspaces.

### 5.3 `auth_session_provider` stays global

Role resolution remains on global `users` (then global `staff`/`managers`/`admins` fallback). In Phase 2 those directories move under companies, but **`auth_session_provider` keeps its global reads for identity resolution** (its `_inferRoleFromDirectory` scans become a legacy fallback that only runs when `users/{uid}` has no role — the common path is one doc read). This is the one file that is deliberately exempt from the FirestorePaths migration.

---

## 6. Migration strategy for services (Phase 2)

### 6.1 The mechanical pattern (one per service)

1. Add `String get _companyId => WorkspaceScope.instance.requireCompanyId();` (or a local `late final _companyId = WorkspaceScope.instance.requireCompanyId()`).
2. Replace `_firestore.collection('staff')` → `_firestore.collection(FirestorePaths.staff(_companyId))`. **Pure find-and-replace of the collection literal** — no query logic changes.
3. Storage refs → `FirebaseStorage.instance.ref(StoragePaths.xxx(slug))`.
4. Add the `firestore.rules` block `match /companies/{companyId}/{document=**}` (see §8.4) and deploy before/with the first scoped write.
5. Verify: `flutter analyze` + targeted manual flow + a `test/firestore_paths_test.dart` + `test/slugify_test.dart`.

### 6.2 Collection mapping table

| Today (global) | Phase 2 target | Notes |
|---|---|---|
| `staff`, `managers`, `admins` | `companies/{c}/staff`… | legacy dirs stay for auth fallback |
| `attendance`, `attendance_logs`, `attendance_alerts` | `companies/{c}/…` | ids unchanged |
| `leave_requests`, `permission_requests`, `checkout_requests` | `companies/{c}/…` | |
| `notifications`, `notification_actions`, `event_dedupe` | `companies/{c}/…` | Cloud Function triggers must follow (coordination) |
| `qr_tokens` | `companies/{c}/qr_tokens` | **tenantId becomes companyId** (§6.4) |
| `geo_config`, `offices` | `companies/{c}/…` | 3 screens |
| `staff_metadata` | `companies/{c}/staff_metadata` | |
| `users` | **stays global** | identity index (§5) |
| `companies` | **stays global** | registry + slug lookup |
| `settings` (`settings/white_label`) | **stays global** | platform default theme |
| `app_config` | **stays global** | bootstrap/admin_access |
| `platformStats`, `activity_logs`, `audit_logs`, `security_events`, `support_tickets`, `billing/*`, platform `announcements` | **stays global** | super-admin platform telemetry, not tenant business data |

### 6.3 Service-by-service notes

- **`notification_service.dart`** (singleton, constructed in `main()` before workspace exists): keep the singleton. `initialize()`/FCM-token registration writes to **global `users/{uid}/fcmToken`** — identity data, stays. All sends/stores (`notifications` collection, dedupe keys) switch to `FirestorePaths.notifications(_companyId)` read **lazily at call time** from `WorkspaceScope` (never at construction). The singleton is fine because `WorkspaceScope` is a static holder.
- **`attendance_service.dart`** (3990 lines, highest risk): mechanical path substitution only, in this order: (1) `attendance`, `attendance_logs`, `attendance_alerts`, (2) `leave_requests`/`permission_requests`/`checkout_requests` if cross-referenced, (3) `staff` reads, (4) `geo_config`/`offices`. The deterministic doc ids `attendance_{safeId}_{dateKey}` (`:2276`) and the `_teamEmployeeIdsStream` full scans are **kept as-is** — scoping per company actually shrinks them. Grep by method name, don't read the file top-to-bottom.
- **`geo_fence_service.dart`, `staff_service.dart`, `payroll_service.dart`, `leave_service.dart`, `permission_service.dart`, `attendance_log_service.dart`, `company_analytics_service.dart`**: same mechanical pattern; each is small enough to finish in one sitting.
- **`company_service.dart`** is the **onboarding owner** in Phase 2: generates companyId (`{slug}_company_001`), calls `WorkspaceService.generateUniqueSlug`, writes `companies/{id}` with `workspaceSlug` + a `slugs/{slug}` reservation in one batch, then creates the admin account as today (writing `workspaceSlug` into `users/{adminUid}`).
- **`platform_service.dart`** (`platformStats`, `audit_logs`, `security_events`, `billing/*`, `support_tickets`, `announcements`): **exempt** from scoping — platform telemetry stays global.
- **`auth_session_provider.dart`**: exempt (§5.3).

### 6.4 `qr_tokens` tenantId → companyId

In `attendance_service.dart` the QR token APIs take a `tenantId` that callers fill with the **admin's auth uid** (`:1905-1966`, `getQrTokenStream`, `markAttendance`). Phase 2: change the parameter name/semantics to `companyId` everywhere and key `companies/{c}/qr_tokens/{companyId}`. `staff_scan_qr_screen` and the client-side `AttendanceService.markAttendance` pass `WorkspaceScope.instance.requireCompanyId()`. **Coordinate with the Vercel cron `qrNotifications.js`** (rotates by tenant in `qr_tokens`) — it must read the same key.

### 6.5 Storage

- `CompanyLogoService.logoPath(companyId)` → `StoragePaths.companyLogo(slug)`; `CompanyLogoService.deleteLogo` → `companies/{slug}/company-logo`.
- `WhiteLabelService.uploadLogo` (`white_label/logo.png`) → `StoragePaths.whiteLabel(slug)`.
- New upload targets per spec: profile-images, employee-documents, payroll, reports, branch-assets (all via `StoragePaths`).

---

## 7. Ordering and phasing

### Phase 1 — Foundation (app keeps working on global collections; no data migration)

Goals: workspace-aware URLs, slug resolution, workspace provider + screens, go_router, auth membership checks, dead-code removal. **No business data moves.**

| # | Task | Files |
|---|---|---|
| 1.1 | Add `go_router` + `flutter_web_plugins`; `flutter pub get` | `pubspec.yaml` |
| 1.2 | `slugify` + unit test | `lib/workspace/utils/slugify.dart`, `test/slugify_test.dart` |
| 1.3 | `Workspace` model + `Workspace.fromCompany` | `lib/workspace/models/workspace.dart` |
| 1.4 | `WorkspaceService` (resolveBySlug, generateUniqueSlug, reserveSlug, streamWorkspace) — pure reads first, no writes to old collections | `lib/workspace/services/workspace_service.dart` |
| 1.5 | `WorkspaceScope` + `FirestorePaths` + `StoragePaths` | `lib/workspace/services/workspace_scope.dart`, `firestore_paths.dart`, `storage_paths.dart`, `test/firestore_paths_test.dart` |
| 1.6 | `WorkspaceProvider` (`loadFromInitialLocation`, `loadBySlug`, `loadById`, `clear`) | `lib/workspace/providers/workspace_provider.dart` |
| 1.7 | Loading / NotFound / AccessDenied screens | `lib/workspace/screens/*.dart` |
| 1.8 | `NavigationService` | `lib/workspace/services/navigation_service.dart` |
| 1.9 | `AppRouter` + redirects; `WorkspaceGate` | `lib/workspace/router/app_router.dart`, `lib/workspace/widgets/workspace_gate.dart` |
| 1.10 | Rewrite `main.dart`: PathUrlStrategy, workspace-aware `WhiteLabelProvider`, delete `CompanyProvider`, `MaterialApp.router`, drop `AnimatedLaunchScreen` + dead routes; `LoginScreen`/`ForgotPasswordScreen` gain `workspaceSlug` + `context.go` post-login; `LandingPage` CTA routes into slug; `AppShell` logout uses `context.go(login)` | `lib/main.dart`, `lib/screens/auth/login_screen.dart`, `forgot_password_screen.dart`, `lib/screens/landing/landing_page.dart`, `lib/screens/app_shell.dart` |
| 1.11 | Auth membership: `companyId`/`workspaceSlug` on `AuthSessionProvider` + cache; `signIn()` workspace check; `WorkspaceGate` check | `lib/providers/auth_session_provider.dart` |
| 1.12 | `flutter analyze` + web smoke test (below) | — |

**Phase 1 verification**
- `flutter analyze` — zero issues.
- `flutter test` — new slugify/firestore_paths tests pass.
- Web smoke (dev server + deployed):
  - `/` → landing.
  - `/green-hospital/login` → login themed with `green-hospital` branding.
  - Bad credentials, then correct creds → `/green-hospital/dashboard` with the right role shell.
  - Unknown slug `/nope/login` → `WorkspaceNotFoundScreen`.
  - Signed-in admin deep links to `/green-hospital/attendance` → correct tab.
  - Sign in as a user of `other-co` at `/green-hospital/login` → cross-workspace error / `AccessDeniedScreen`.
  - Hard refresh at `/green-hospital/dashboard` → stays on that URL (no `#`, no bounce to splash).
  - Super admin → `/admin` only; visiting `/{slug}/…` redirects there.

### Phase 2 — Scoping migration (mechanical, per collection)

| # | Task | Files |
|---|---|---|
| 2.1 | `firestore.rules`: add `match /companies/{companyId}/{document=**}` scoped by `inCompany(companyId)`; `firestore.indexes.json`: `companies` + `workspaceSlug` single-field (auto) and any composite the slug page needs; deploy | `firestore.rules`, `firestore.indexes.json` |
| 2.2 | Storage: `CompanyLogoService`, `WhiteLabelService` → `StoragePaths`; company slug available at call sites via `WorkspaceScope` | `lib/services/company_logo_service.dart`, `white_label_service.dart` |
| 2.3 | Onboarding: `companyId` = `{slug}_company_{seq}`, unique slug reservation batch, `workspaceSlug` written to `companies/{id}` + `users/{adminUid}` | `lib/services/company_service.dart`, `manager_account_service.dart` |
| 2.4 | Read-mostly scope first: `settings`, `geo_config`, `offices`, `staff_metadata`, `staff`/`managers`/`admins` in `staff_service`/`leave_service` | `lib/services/{staff,leave,geo_fence,attendance_log}_service.dart`, `lib/screens/{staff/staff_scan_qr,geo_tag/geo_tag,employee/employee_home}_screen.dart` |
| 2.5 | Requests: `leave_requests`, `permission_requests`, `checkout_requests` | `lib/services/{leave,permission}_service.dart`, screens |
| 2.6 | Attendance core: `attendance`, `attendance_logs`, `attendance_alerts`, `qr_tokens` (**tenantId→companyId**), `notifications`/`notification_actions`/`event_dedupe` | `lib/services/{attendance,notification}_service.dart`, `lib/screens/staff/staff_scan_qr_screen.dart` |
| 2.7 | `CompanyRepository` wired to read/write `companies/{c}/companyInfo|settings|subscription`; `WorkspaceProvider` merges them; branding editor writes company doc | `lib/workspace/services/company_repository.dart`, `lib/workspace/providers/workspace_provider.dart`, `lib/screens/admin/white_label_screen.dart` |
| 2.8 | Backfill script (admin-run): copy legacy top-level docs into `companies/{c}/…`; update `users/{uid}` with `workspaceSlug`; sweep every remaining `collection(` site | one-off script under `tool/` |
| 2.9 | Final grep for `collection('` excluding global allow-list; `flutter analyze`; full manual regression of admin/employee flows | — |

**Phase 2 verification per step:** `flutter analyze`; `test/firestore_paths_test.dart` extended; manual flow for the scoped feature (check-in/out, leave submit/approve, payroll export, notifications); a **cross-tenant isolation smoke**: user A must not see company B's attendance after both migrate.

---

## 8. Risks & pitfalls

### 8.1 go_router + imperative navigation coexistence
The 11 imperative sites (`login_screen.dart:75`, `app_shell.dart:330`, `forgot_password_screen.dart:169`, `landing_page.dart`, super-admin detail pushes) all navigate **to screens we're making routes** — each must become `context.go/push`. Every other `Navigator.push(MaterialPageRoute(...))` in the codebase continues to work (go_router uses the root Navigator under the hood). The single must-fix: the `routes:` named map and the `AuthGateScreen`/`AnimatedLaunchScreen` pushes. Grep for `pushNamed` returns nothing today, so no named-route landmines.

### 8.2 AppShell / EmployeeHome index nav vs routes
Accepted Phase-1 drift: internal tab `setState` doesn't update the URL; URL-driven tab switches rebuild the shell (state loss for in-flight streams/timers). Mitigation: keep the shells mounted as long as the user stays on one route, and land on the correct tab for deep links. `StatefulShellRoute.indexedStack` is the documented follow-up; do not attempt it in the same change as the router swap.

### 8.3 WhiteLabelProvider re-theming per workspace
The biggest silent-bug risk. `WhiteLabelProvider` currently self-listens in `create()` (`white_label_provider.dart:24`) — after Phase 1 it must **not** hold two competing streams (platform default + workspace). Single subscription, switched when `WorkspaceProvider` transitions. Also: `white_label_screen.dart` writes to the **global** `settings/white_label` today — in Phase 2 it must write `companies/{companyId}` branding, or every tenant will re-brand the platform default.

### 8.4 Firestore rules: subcollections currently denied
`match /companies/{companyId}` (`firestore.rules:69`) has **no `{document=**}`**, so `companies/{c}/users` etc. are denied until rules are updated. Add `match /companies/{companyId}/{document=**}` guarded by `inCompany(companyId)` **before** Phase 2 deploys, and note `inCompany` reads `users/{uid}.companyId`, which stays global — so the rules' identity model is unchanged. Also update the `companies` read to allow the anonymous/signed-out slug lookup if the landing page needs to verify a slug pre-login (today all reads require `signedIn()`).

### 8.5 Web Firebase project mismatch
All platforms (`lib/firebase_options.dart`) and the deploy target now point at the single production project **`trakradminsetup-28437`** (web app id `1:6848613159:web:3250e45472fa6762137702`). If a future migration splits platforms across projects, run `flutterfire configure` against the new project and add the `assert`/`debugPrint` in §4 so stale config is loud, not silent.

### 8.6 Slug uniqueness race
Two simultaneous onboardings of the same name both find `slug` free. The `slugs/{slug}` reservation doc + company doc in one **batch** makes the write atomic: second writer's batch fails on the duplicate doc id, catches, retries `slug-1`. Do not rely on a pre-write query alone.

### 8.7 Index requirements
`companies where workspaceSlug == X` is a single-field equality → **auto-indexed**, no composite needed. Add an explicit entry in `firestore.indexes.json` only if the page adds `orderBy(createdAt)` to that query. The existing `collectionGroup` indexes for `attendance`/`permission_requests`/`checkout_requests` are unaffected because Phase 2 moves to per-company **subcollections** (no collectionGroup queries remain; the existing group indexes become unused but harmless).

### 8.8 Path strategy + hosting rewrite
`firebase.json` already rewrites `** → /index.html`, so `usePathUrlStrategy()` works in production. Dev (`flutter run -d chrome`) also serves paths fine with the same call. Trap: **firebase auth / google sign-in redirect URIs** are host-dependent — after adopting path URLs, ensure the Firebase console authorized domains include the deployed host, or `signInWithPopup` breaks on the new domain.

### 8.9 Backend coupling (Vercel serverless, no Cloud Functions)
This project runs on the Firebase **Spark plan** — Cloud Functions are removed. All server-side logic lives in `vercel_backend/api/` (`sendNotification.js`, `notificationAction.js`, `broadcastNotification.js`, `qrNotifications.js`, `syncMissedCheckout.js`, `attendanceReminders.js`). These target **top-level collections** (`notifications`, `qr_tokens`, `checkout_requests`, `attendance`). Phase 2 moves these under `companies/{c}/…` — the Vercel endpoints must be updated to match the new paths and the tenant→companyId key change, in the **same release** as step 2.6, or push notifications/QR rotation silently die. Client-only change is never enough here.

### 8.10 attendance_service (3990 lines) and no test suite
The only real tests after Phase 1 are `slugify`/`firestore_paths`. For `attendance_service` keep edits **mechanical path substitutions**, never refactor query semantics in the same diff; verify each touched method via its manual flow (check-in, temp-exit, re-entry, checkout, weekly/monthly streams, missed-checkout sync) and keep `tenantId→companyId` and deterministic id logic byte-identical apart from the key change. Add `test/attendance_paths_test.dart` asserting the new doc paths before touching the big file.

### 8.11 `users` global doc vs multi-tenant identity
The `users/{uid}` doc holds `role` + `companyId` and is written by `register()`, Google sign-in, and admin fallback. Keeping it global is correct (§5) but means a malicious or buggy write can't be scoped by company path — the security model leans entirely on the `users` doc's integrity. Phase 3 hardening: make `users/{uid}` immutable after creation except via admin paths, and enforce `sameCompany` on writes (already in rules).
