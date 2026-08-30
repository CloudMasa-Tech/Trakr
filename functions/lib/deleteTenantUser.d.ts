/**
 * HTTP Cloud Function: deleteTenantUser (onRequest)
 *
 * Permanently deletes a single Firebase Auth user record from a TENANT project.
 * This is the server-side half of the "Delete Employee/Manager" action in the
 * tenant app: the Flutter client removes the Firestore directory + role docs
 * itself, then asks this function to remove the Auth account so the person can
 * no longer sign in to that tenant at all.
 *
 * Why it lives on the MASTER project:
 *   Tenant projects run on the Firebase Spark plan, so they have NO Cloud
 *   Functions and the client SDK can only delete the *currently signed-in*
 *   user. Auth-user deletion requires the Firebase Admin SDK, which is only
 *   available server-side. The master project (Blaze) is the natural control
 *   plane because it already holds the SERVICE_ACCOUNT_JSON secret and the
 *   workspace registry that maps tenant admins to their projects.
 *
 * Authorization (two accepted paths):
 *   PATH A — Platform operator: caller holds a super_admin claim on the MASTER
 *            project (same check as deleteWorkspace/deployTenantRules).
 *   PATH B — Tenant Company Admin: caller's ID token is minted by the TENANT
 *            project (verified via the master service account scoped to that
 *            project), and the token's email matches the `adminEmail` recorded
 *            in the master `workspaces` registry for that `projectId`.
 *
 * Request body (callable envelope {"data": {...}} or flat body):
 *   { "projectId": "<tenant firebase project id>",
 *     "uid":   "<target auth uid>",        // optional, preferred
 *     "email": "<target auth email>" }     // used when uid is absent
 *
 * Response: {"result": {"success": true, "projectId", "uid", "email", "deletedAt"}}
 *
 * Requirements / IAM:
 *   - SERVICE_ACCOUNT_JSON secret (master SA) must be configured.
 *   - The master SA MUST be granted `roles/firebaseauth.admin` on every tenant
 *     project before DELETE is allowed (one-time folder-level IAM grant under
 *     folders/818058604638). Without it the call fails with a clear message.
 */
export declare const deleteTenantUser: import("firebase-functions/v2/https").HttpsFunction;
//# sourceMappingURL=deleteTenantUser.d.ts.map