/**
 * HTTP Cloud Function: deployTenantRules (onRequest)
 *
 * Deploys Firestore rules and indexes to a tenant project programmatically
 * using the Firebase Admin SDK and Security Rules REST API.
 *
 * Invoked by the Flutter app during tenant provisioning after the tenant
 * Firebase project is verified but before admin onboarding begins.
 *
 * NOTE: Converted from onCall to onRequest because the Flutter Web client
 * invokes this endpoint via raw fetch/http.post with an EXPLICIT
 * `Authorization: Bearer <idToken>` header (the callable SDK was observed
 * sending empty Authorization headers). Auth is therefore verified manually
 * via admin.auth().verifyIdToken() + super_admin claim check.
 *
 * Request body: {"data": {"tenantProjectId": "..."}} (callable envelope kept
 * for compatibility; a flat body is also accepted).
 * Response body: {"result": {...}} on success, {"error": {...}} on failure.
 *
 * Requires: Caller must be an authenticated superadmin (custom claim super_admin == true)
 * Secret: SERVICE_ACCOUNT_JSON (master project service account with IAM roles on tenant project)
 *
 * IAM roles required on TENANT project for the master service account:
 * - roles/firebaserules.admin (deploy rules)
 * - roles/datastore.indexAdmin (deploy indexes)
 */
/**
 * HTTP entrypoint: CORS + manual Bearer-token auth + callable-style
 * request/response envelope.
 */
export declare const deployTenantRules: import("firebase-functions/v2/https").HttpsFunction;
//# sourceMappingURL=deployTenantRules.d.ts.map