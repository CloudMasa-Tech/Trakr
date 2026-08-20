/**
 * Callable Cloud Function: createTenantProject
 *
 * Creates a new GCP/Firebase project under the specified folder using the
 * Cloud Resource Manager API v3. This function is called during tenant
 * provisioning to automatically create the Firebase project instead of
 * requiring manual creation in the Firebase Console.
 *
 * Full provisioning pipeline (all steps must succeed or the function throws):
 *   1. Collision-free project ID generation
 *   2. GCP project creation via CRM v3
 *   3. Firebase enablement via Firebase Management API (wait for completion)
 *   4. Required API enablement via Service Usage API (wait for completion)
 *   5. Firestore database creation in Native mode (wait for completion)
 *   6. Email/Password auth provider enablement via Firebase API provisioning
 *      - GET the current config first for diagnostics
 *      - Ensure a Firebase Web app exists for the project
 *      - Provision auth through firebase:provisionFirebaseApp with firebaseAuthInput
 *   7. Firestore rules + indexes deploy (NOT done here — done by tenant_provisioner)
 *
 * Requires: Caller must be an authenticated superadmin (custom claim super_admin == true)
 * Secret: SERVICE_ACCOUNT_JSON (master project service account with IAM roles on folder)
 *
 * IAM roles required on FOLDER (818058604638) for the master service account:
 * - roles/resourcemanager.projectCreator
 * - roles/firebase.projectAdmin
 * - roles/serviceusage.serviceUsageAdmin
 * - roles/firebaserules.admin
 * - roles/datastore.indexAdmin
 *
 * @param data.projectId - The desired Firebase project ID (must be globally unique)
 * @param data.companyName - The company/workspace name (used to derive display name)
 * @param data.billingAccount - Optional billing account ID (e.g., "billingAccounts/XXXXXX")
 * @returns { success, message, projectId, projectNumber, projectName, displayName,
 *            folderId, projectIdChanged, originalProjectId, firebaseEnabled, apisEnabled,
 *            firestoreDbCreated, authEnabled, alreadyExisted, durationMs }
 * @throws HttpsError if not superadmin, invalid input, or any provisioning step fails
 */
export declare const createTenantProject: import("firebase-functions/v2/https").CallableFunction<any, Promise<{
    success: boolean;
    message: string;
    projectId: string;
    projectNumber: string;
    projectName: string;
    displayName: string;
    folderId: string;
    projectIdChanged: boolean;
    originalProjectId: string | undefined;
    alreadyExisted: boolean;
    firebaseEnabled: boolean;
    apisEnabled: boolean;
    firestoreDbCreated: boolean;
    authEnabled: boolean;
    durationMs: number;
}>, unknown>;
//# sourceMappingURL=createTenantProject.d.ts.map