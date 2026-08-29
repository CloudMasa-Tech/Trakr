# QA: "Reports to" Dropdown Fix

Feature under test: the **Reports to** dropdown on the Onboard User dialog
(`lib/screens/manager/onboard_user_dialog.dart`) now lists eligible users
(admins / managers / any role with `canBeReportingManager`) from the tenant's
`users` collection, plus a `canBeReportingManager` toggle in
**User Role Management** (`lib/screens/admin/user_roles_screen.dart`).

## Verification findings

### 1. Edge cases in `_loadManagers()` — HARDENED
- `getAllRoles().first` is wrapped in try/catch; if it fails the dropdown is
  shown empty instead of hanging.
- `eligibleRoleIds.isEmpty` (brand-new tenant with no roles, or no eligible
  role) short-circuits to an empty list — no Firestore query is run.
- The `users` query never executes if there are no eligible role IDs, so a
  fresh-tenant race (admin doc still being written) cannot throw; it simply
  yields "No eligible managers found".
- Deleted / renamed roles: not present in `eligibleRoleIds`, so excluded by the
  `whereIn`. No crash.
- `whereIn` is capped at `.take(30)` to respect Firestore's 30-value limit.
- Users without a `name` are skipped; `roleName` falls back to `roleId`.
- **Added:** a real load failure now surfaces
  `Could not load managers. Check your connection and try again.` (orange) and
  is `debugPrint`-ed, instead of failing silently.

### 2. Persisted field consistency — CONFIRMED
`StaffService.addStaff` (`lib/services/staff_service.dart:46`) writes to
**`users/{uid}`**:
```
'reportsToUserId': staff.reportsToUserId,
```
and to the `staff` doc via `staff.toMap()` (which includes both `reportsTo`
name and `reportsToUserId`).

Downstream readers:
- `lib/models/manager_model.dart:83` reads `reportsToUserId` from `users` →
  field name matches.
- Manager Log / org views (`manager_team_members_screen.dart:86`,
  `permission_service.dart`, `attendance_service.dart`, `leave_service.dart`)
  match by **`staff.reportsTo` (name string)** → the employee's `reportsTo`
  (manager name) is exactly what we store, so grouping is correct.

No naming mismatch. Both `reportsTo` (name) and `reportsToUserId` are persisted
and consumed consistently.

### 3. Access guard for the onboarding screen — TRACED
The dialog is opened from two places:
- **Team Directory** (`team_directory_screen.dart:126`): `onboarderRole:
  auth.role ?? AppUserRole.admin` → admins can onboard managers + employees.
- **Manager Team Members** (`manager_team_members_screen.dart:65`):
  `onboarderRole: AppUserRole.employee` → managers can only onboard employees.

Inside the dialog, manager-role assignment is gated by
`_canAssignManager => widget.onboarderRole == AppUserRole.admin`
(`onboard_user_dialog.dart:100`). The dialog is only reachable from
admin/manager screens, which are role-gated in the app navigation.

**Recommendation (not blocking):** there is currently no explicit
`staff.manage` / `users.manage` permission check on the FAB that opens the
dialog — access relies on role-based screen visibility. For defense-in-depth,
consider wrapping the FAB's `onPressed` with an explicit permission check
(`_accessControl.hasPermission(userId, 'staff.manage')`).

## Manual test checklist

### A. Fresh tenant / first employee
- [ ] Create a brand-new workspace, sign in as the bootstrap admin.
- [ ] Open **Onboard User** → the **Reports to** dropdown loads without hanging.
- [ ] With only the admin present: dropdown shows the admin ("Full Name —
      Company Admin / Admin") or "No eligible managers found" if no eligible
      user exists yet — never crashes.
- [ ] Onboard an employee with a manager selected; submit succeeds.

### B. "Eligible as reporting manager" toggle
- [ ] Go to **Admin → User Roles Management**.
- [ ] Open a role (e.g. Manager) → toggle **"Eligible as reporting manager"**
      is ON by default for admin/company_admin/manager and managerial roles.
- [ ] Turn it OFF for a custom role → save.
- [ ] Re-open Onboard User → users with that role no longer appear in the
      dropdown.
- [ ] Turn it back ON → users with that role reappear.
- [ ] Reload the app / new session → toggle state persists (read from Firestore
      `roles` doc `canBeReportingManager`).

### C. Employee appears under Manager in Manager Log / org views
- [ ] Onboard Employee E with **Reports to = Manager M**.
- [ ] Open **Manager → Team Members** (or Manager Log) as M → E is listed under
      M.
- [ ] Confirm `users/{E.uid}.reportsToUserId == M.uid` and
      `staff/{E}.reportsTo == "M name"` in Firestore.
- [ ] Edit E later and change Reports to = Manager N → E moves under N.

### D. Error / resilience
- [ ] Toggle airplane mode, open Onboard User → dropdown shows the orange
      "Could not load managers…" message, not a silent empty list.
- [ ] Re-enable network, reopen → dropdown populates normally.
