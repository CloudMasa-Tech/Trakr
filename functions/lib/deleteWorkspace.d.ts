/**
 * Callable Cloud Function: deleteWorkspace
 *
 * Permanently deletes a tenant workspace and its associated GCP/Firebase project.
 * This is an irreversible operation that requires superadmin privileges.
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
 *
 * @param data.workspaceId - The workspace ID to delete
 * @param data.projectId - The Firebase project ID to delete (must match workspace)
 * @param data.confirmation - Must be "DELETE" to confirm irreversible action
 * @returns { success, message, projectId, workspaceId, deletedAt }
 * @throws HttpsError if not superadmin, invalid input, or deletion fails
 */
export declare const deleteWorkspace: import("firebase-functions/v2/https").CallableFunction<any, Promise<{
    success: boolean;
    message: string;
    workspaceId: string;
    projectId: string;
    deletedAt: string;
}>, unknown>;
//# sourceMappingURL=deleteWorkspace.d.ts.map