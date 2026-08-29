# QA — Admin Provisioning & "Reports to" Manual Test Checklist

Live-fire verification for the admin-provisioning fix. `flutter analyze` cannot
prove a real tenant was provisioned correctly, so this must be run against a
live Firebase project (one with a tenant project already created, per the
multi-tenant flow).

Expected behavior after the fix:
- A freshly provisioned bootstrap admin gets a **complete** `users/{uid}` doc
  immediately (no login-time repair needed).
- An admin invited via "Add Secondary Admin" also gets a **complete**
  `users/{uid}` doc at invite time.
- Both admins appear in the **"Reports to"** dropdown when onboarding a new
  user.

---

## 0. Prerequisites

- A working tenant Firebase project (Firestore + Email/Password auth enabled).
- The app running against that tenant project.
- Firestore console open to the tenant project.
- A known admin email you will onboard and later sign in as.

---

## a. Bootstrap flow — provision a brand-new workspace

1. As Operator/Super Admin, provision a new workspace (or re-run provisioning on
   a fresh one).
2. Open **Firestore console** → `users/{adminUid}` for the bootstrap admin.
   Confirm **immediately after provisioning, with NO further login**:
   - `roleId` == `"company_admin"`
   - `roleName` == `"Company Admin"`
   - `roleLevel` == `80`
   - `companyId` == the new workspace id
   - `permissionIds` is a non-empty list
   - `hasRegistered` == `true`
3. Also open `roles/company_admin` and confirm `level` == `80`
   (== `kCompanyAdminRoleLevel` — no drift between the two old hardcoded 80s).

---

## b. Invite flow — "Add Secondary Admin"

1. Sign in as the bootstrap admin (tenant app).
2. Go to **Profile Setting** (left sidebar, index 17) → **Add Secondary Admin**.
3. Enter a name/email/phone + a temporary password for the new admin. Submit.
4. Open Firestore console → `users/{newAdminUid}`. Confirm **at invite time**:
   - `roleId` == `"company_admin"`
   - `roleName` == `"Company Admin"`
   - `roleLevel` == `80`
   - `companyId` matches
   - `permissionIds` is a non-empty list
   - `hasRegistered` == `true`
5. Log out. Complete the new admin's **first sign-in** with the provided
   credentials. Confirm Firestore console still shows the complete doc above
   (nothing missing — and nothing was repaired/fudged by a login-time path).

---

## c. "Reports to" shows both admins

1. Sign in as **either** admin.
2. Open **Onboard Employee** (`OnboardUserDialog`).
3. In the **"Reports to"** dropdown confirm BOTH admins appear, labeled with
   their name and the role name, e.g.:
   - `Jane Doe — Company Admin`
   - (email shown below the name)
   - and the second admin similarly.
4. The label uses the exact format `"{name} — {roleName}"` from
   `onboard_user_dialog.dart` `_buildManagerDropdown()` (em-dash).

---

## d. Onboard an employee reporting to an admin

1. Select one of the admins in **"Reports to"** and fill the rest of the form.
2. Submit. Confirm the employee's `staff` doc has `reportsTo` == the selected
   admin's name.
3. In **Manager Log** / team views, confirm the employee shows up under the
   correct admin's team.

---

## e. Role-level drift check

1. Open Firestore console.
2. Confirm `roles/company_admin` → `level` == `80`.
3. Confirm every admin `users/{uid}` → `roleLevel` == `80`.
4. All three reference the single `kCompanyAdminRoleLevel = 80` constant
   (`tenant_defaults.dart`), so they cannot drift.

---

## Pass criteria

- All fields in sections a. and b. are populated at creation time.
- No permission-denied errors in the console while onboarding/provisioning.
- Both admins visible in **"Reports to"** with the `— Company Admin` label.
- `roles/company_admin.level` and all admin `roleLevel`s are `80`.
