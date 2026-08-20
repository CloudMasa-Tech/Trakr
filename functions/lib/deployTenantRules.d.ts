/**
 * Callable Cloud Function: deployTenantRules
 *
 * Deploys Firestore rules and indexes to a tenant project programmatically
 * using the Firebase Admin SDK and Security Rules REST API.
 *
 * Invoked by the Flutter app during tenant provisioning after the tenant
 * Firebase project is verified but before admin onboarding begins.
 *
 * Requires: Caller must be an authenticated superadmin (custom claim super_admin == true)
 * Secret: SERVICE_ACCOUNT_JSON (master project service account with IAM roles on tenant project)
 *
 * IAM roles required on TENANT project for the master service account:
 * - roles/firebaserules.admin (deploy rules)
 * - roles/datastore.indexAdmin (deploy indexes)
 *
 * @param data.tenantProjectId - The Firebase project ID of the tenant project
 * @returns { success, message, ruleset, indexesCreated, indexesSkipped }
 * @throws HttpsError if not superadmin, invalid input, or deployment fails
 */
export declare const deployTenantRules: import("firebase-functions/v2/https").CallableFunction<any, Promise<{
    success: boolean;
    message: string;
    ruleset: string;
    durationMs: number;
}>, unknown>;
//# sourceMappingURL=deployTenantRules.d.ts.map