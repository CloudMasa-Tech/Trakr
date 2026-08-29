# Changelog — "Reports to" / Admin-Provisioning Fix

Review summary for the whole bug-fix effort (root cause → consolidation → invite
flow). Every file touched, with a one-line description.

## Root cause
The "Reports to" dropdown (`OnboardUserDialog._loadManagers`) only lists a user
as an eligible reporting manager when their `users/{uid}` doc carries a
`roleId` that maps to a role with `canBeReportingManager == true`. The tenant's
top authority is the Company Admin. That doc was sometimes missing/partial
(no `roleId`/`companyId`), so the admin never appeared in the list.

---

## Fixes

### 1. Root cause — dropdown eligibility
- **`lib/screens/manager/onboard_user_dialog.dart`**
  Rewrote `_loadManagers()` to source candidates from the canonical
  `users` stream + `roles` (via `AccessControlService`), requiring a non-empty
  `roleId` whose role is `canBeReportingManager`, scoped by `companyId`, and
  de-duplicated by name. A missing/partial admin doc can no longer be skipped
  silently — the fix guarantees the doc itself is complete (below). Also
  hardened the dropdown (loading/empty states, defensive error handling).

### 2. Defensive login-time repair (fallback for pre-existing broken tenants)
- **`lib/providers/auth_session_provider.dart`**
  Added `_repairBootstrapAdminUsersDoc()`, called from `_loadRole()` before the
  stored-role short-circuit. If the signed-in bootstrap primary admin's
  `users/{uid}` doc is missing RBAC fields, it backfills `roleId:
  'company_admin'`, `roleName`, `roleLevel:80`, `companyId` (`workspaceId`),
  `hasRegistered:true`. Permission-denied-safe.

- **`firestore.rules`** (and the deployed `functions/src/assets/firestore.rules`,
  when re-synced)
  Added `isBootstrapAdminSelfRepair(userId)` — a narrow, additive OR on the
  `users/{userId}` update rule that only lets the recorded primary bootstrap
  admin self-write the previously-missing `roleId: 'company_admin'` onto their
  own doc. Guarded by `request.auth.uid == userId`,
  `!('roleId' in resource.data)`, `isSeededBootstrapAdmin()`, and the exact
  target value. Does not weaken `unchangedPrivileges()`.

### 3. roleLevel consolidation (single source of truth)
- **`lib/control_plane/services/tenant_defaults.dart`**
  Added `const int kCompanyAdminRoleLevel = 80` plus a shared builder
  `buildCompanyAdminUserDoc(...)` that returns the complete company-admin
  `users/{uid}` data (role, roleId, roleName, roleLevel, companyId, full
  `permissionIds` catalog, `hasRegistered`).

- **`lib/control_plane/services/tenant_provisioner.dart`** (bootstrap flow)
  The admin `users/{uid}` write now calls `buildCompanyAdminUserDoc(...)` and
  uses `kCompanyAdminRoleLevel` (replacing a hardcoded 80). The admin `admins`
  write also uses the constant.

- **`lib/control_plane/services/tenant_seeder.dart`**
  The seeded `roles/company_admin` doc now sets `level: kCompanyAdminRoleLevel`
  (so the role doc and the admin `roleLevel` can never drift). Also removed the
  duplicate `app_config/admin_access` write (it is created by the provisioner
  step 2a, which must run first for rule ordering).

### 4. Invite flow — complete users/{uid} at invite time
- **`lib/services/manager_account_service.dart`**
  `createCompanyAdminAccount()` (the "Add Secondary Admin" invite path) now
  writes the invited admin's `users/{uid}` doc via the shared
  `buildCompanyAdminUserDoc(...)` — previously it omitted `permissionIds` and
  `hasRegistered` and hardcoded the level. The invited admin's doc is now as
  complete as the bootstrap admin's, so they appear in "Reports to" immediately
  after their first login, with no repair step.

### 5. Supporting / scaffolding (this effort)
- **`lib/services/access_control_service.dart`** — permission/RBAC helpers used
  by the new shared builder and the dropdown (imports/catalog wiring).
- **`lib/models/user_role.dart`** — role level field used by the seeded role doc.
- **`lib/screens/app_shell.dart`, `lib/widgets/common/sidebar.dart`,
  `lib/theme/app_theme.dart`, several `lib/screens/admin/*`** — lint/style
  fixes (`withValues`, `context.mounted`, `prefer_const`) required to keep
  `flutter analyze` clean; no behavior change.
- **`functions/src/deployTenantRules.ts` / `lib/` copy-assets** — deploy path
  for tenant rules (source of `functions/src/assets/firestore.rules`).
- **`pubspec.yaml`** — added the transparent logo asset for the landing page.

---

## Manual verification
See `QA_admin_provisioning.md` for the step-by-step live checklist.

## Deployment note (important)
The defensive fallback (`isBootstrapAdminSelfRepair`) only takes effect once the
updated tenant rules are deployed: `firestore.rules` is the editable source; the
**actually-deployed** tenant rules are `functions/src/assets/firestore.rules`
(via `deployTenantRules`). After this change, re-deploy tenant rules so the
update rule includes the repair helper — otherwise pre-existing broken tenants
will still be permission-denied on the repair (newly provisioned and newly
invited admins are unaffected, since their docs are complete at creation).
