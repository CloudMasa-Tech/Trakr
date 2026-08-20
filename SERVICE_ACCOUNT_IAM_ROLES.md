# Service Account IAM Roles for Automated Tenant Provisioning

## Required Roles (Folder-Level — Inherited by Tenant Projects)

The master service account (`trakradminsetup-28437@appspot.gserviceaccount.com`) MUST have the following IAM roles **on folder `818058604638` (tenant-projects)**. These roles are automatically inherited by all tenant projects created under this folder via IAM inheritance.

| Role | Purpose | API Used |
|------|---------|----------|
| `roles/resourcemanager.projectCreator` | Create new GCP/Firebase projects under the folder | Cloud Resource Manager API (`cloudresourcemanager.googleapis.com/v3/projects`) |
| `roles/firebaserules.admin` | Deploy Firestore rules via `firebaserules.googleapis.com` | Firebase Rules API |
| `roles/datastore.indexAdmin` | Deploy Firestore indexes via `firestore.googleapis.com` | Firestore Admin REST API |

## Assignment Instructions (One-Time Setup)

**Run these commands once to grant the roles on the folder:**

```bash
# Grant Project Creator role on the folder
gcloud resource-manager folders add-iam-policy-binding 818058604638 \
  --member="serviceAccount:trakradminsetup-28437@appspot.gserviceaccount.com" \
  --role="roles/resourcemanager.projectCreator"

# Grant Firebase Rules Admin on the folder (inherited by tenant projects)
gcloud resource-manager folders add-iam-policy-binding 818058604638 \
  --member="serviceAccount:trakradminsetup-28437@appspot.gserviceaccount.com" \
  --role="roles/firebaserules.admin"

# Grant Datastore Index Admin on the folder (inherited by tenant projects)
gcloud resource-manager folders add-iam-policy-binding 818058604638 \
  --member="serviceAccount:trakradminsetup-28437@appspot.gserviceaccount.com" \
  --role="roles/datastore.indexAdmin"
```

**Verify the grants:**

```bash
gcloud resource-manager folders get-iam-policy 818058604638 \
  --flatten="bindings[].members" \
  --filter="bindings.members:trakradminsetup-28437@appspot.gserviceaccount.com" \
  --format="table(bindings.role)"
```

## How It Works (Automatic IAM Inheritance)

1. **Project Creation**: `createTenantProject` Cloud Function creates the GCP project under folder `818058604638` (tenant-projects) using Cloud Resource Manager API v3 with `parent: folders/818058604638`.

2. **Automatic Inheritance**: The new project automatically inherits all IAM roles granted on the parent folder. The master service account immediately has `firebaserules.admin` and `datastore.indexAdmin` on the new tenant project.

3. **Zero Manual Steps**: No per-project IAM grants needed. The `deployTenantRules` and `createTenantProject` Cloud Functions work immediately on the newly created project.

## Security Constraints (Enforced in Code)

The `createTenantProject` and `deployTenantRules` Cloud Functions enforce these guards at runtime:

```typescript
// In createTenantProject:
_assertNotMasterProject(tenantProjectId, 'createTenantProject');
_checkProjectIdFormat(projectId);
_verifySuperAdminClaim(context.auth);

// In deployTenantRules:
_verifySuperAdminClaim(context.auth);
_validateProjectIdFormat(tenantProjectId);
```

**No code path can ever write to the master project** — the functions explicitly refuse to operate on the master project ID (`trakradminsetup-28437`).

## Audit Logging

Every automated step logs the exact tenant project ID:

```
TenantProvisioner.provision: step "create tenant project if needed" starting…
TenantProvisioner.provision: step "create tenant project if needed" succeeded.
TenantProvisioner.provision: step "validate tenant project connection" succeeded.
TenantProvisioner.provision: step "deploy tenant Firestore rules and indexes" succeeded.
```

These logs appear in:
- Flutter debug console during provisioning
- `workspace_provision_logs/{logId}` Firestore document (Master project)
- Google Cloud Console → Logging → Logs Explorer (filter by `resource.type="firebase_project" AND labels.project_id="<tenant-project-id>"`)

## Verification Procedure (Post-Provisioning)

After provisioning a test tenant (e.g., `sample1-47c03`):

1. Open Google Cloud Console → IAM & Admin → Audit Logs
2. Filter: `resource.type="firebase_project" AND protoPayload.resourceName="projects/sample1-47c03"`
3. Confirm API calls present:
   - `cloudresourcemanager.googleapis.com/v3/projects` (CREATE) — project creation
   - `firebase.googleapis.com/v1beta1/projects/sample1-47c03:addFirebase` (POST) — Firebase enablement
   - `serviceusage.googleapis.com/v1/projects/sample1-47c03/services:batchEnable` — API enablement
   - `firebaserules.googleapis.com/v1/projects/sample1-47c03/rulesets` (CREATE)
   - `firebaserules.googleapis.com/v1/projects/sample1-47c03/releases` (CREATE)
4. **Confirm NO audit log entries for the master project ID** (e.g., `trakradminsetup-28437`) during this provisioning run.
5. **Verify project parent**: In Cloud Console → IAM & Admin → Resource Manager, the project should show parent folder `818058604638` (tenant-projects).

## What's Now Automatic (No Manual Steps)

The following are now **fully automated** — no manual Firebase Console steps required:

1. ✅ **Create GCP/Firebase project** — via `createTenantProject` Cloud Function
2. ✅ **Grant IAM roles** — automatic via folder-level inheritance
3. ✅ **Enable Firebase services** — via Firebase Management API (`addFirebase`)
4. ✅ **Enable required APIs** — Firestore, Auth, RTDB, Storage, Cloud Functions
5. ✅ **Deploy Firestore rules & indexes** — via `deployTenantRules` Cloud Function
6. ✅ **Create Company Admin auth account** — via client SDK on tenant project
7. ✅ **Seed tenant defaults** — departments, policies, QR token, roles/permissions

## What Remains Manual (One-Time Only)

The Super Admin must perform this **once** during initial setup:

1. **Grant folder-level IAM roles** — Run the three `gcloud` commands above once to grant the master service account the required roles on folder `818058604638`. After this, all future tenant projects are fully automated.

## What Remains Manual (Per Tenant — Optional)

The Super Admin may still need to perform these in Firebase Console for each tenant if not covered by automation:

1. **Configure Email/Password auth providers** beyond the basic enablement (e.g., password strength, account linking)
2. **Configure authorized domains** for OAuth redirects
3. **Set up custom SMTP** for password reset emails (if not using default)