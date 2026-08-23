/**
 * HTTP Cloud Function: deleteWorkspace (onRequest)
 *
 * Permanently deletes a tenant workspace and its associated GCP/Firebase project.
 * This is an irreversible operation that requires superadmin privileges.
 *
 * NOTE: Converted from onCall to onRequest because the Flutter Web client
 * invokes this endpoint via raw fetch/http.post with an EXPLICIT
 * `Authorization: Bearer <idToken>` header (the callable SDK was observed
 * sending empty Authorization headers). Auth is therefore verified manually
 * via admin.auth().verifyIdToken() + super_admin claim check.
 *
 * Request body: {"data": {"workspaceId","projectId","confirmation"}} (callable
 * envelope kept for compatibility; a flat body is also accepted).
 * Response body: {"result": {...}} on success, {"error": {...}} on failure.
 *
 * Flow:
 * 1. Validates superadmin authorization
 * 2. Validates input (workspaceId, projectId)
 * 3. Deletes the GCP/Firebase project using Cloud Resource Manager API
 * 4. After successful project deletion, cleans up master Firestore records
 * 5. Records audit log with deletion details and 30-day reuse block
 *
 * Requirements:
 * - Caller must be authenticated superadmin (custom claim super_admin == true)
 * - Master service account needs roles/resourcemanager.projectDeleter on the folder
 * - SERVICE_ACCOUNT_JSON secret must be configured
 */
/**
 * HTTP entrypoint: CORS + manual Bearer-token auth + callable-style
 * request/response envelope.
 */
export declare const deleteWorkspace: import("firebase-functions/v2/https").HttpsFunction;
//# sourceMappingURL=deleteWorkspace.d.ts.map