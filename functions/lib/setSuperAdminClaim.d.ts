/**
 * Callable Cloud Function: setSuperAdminClaim
 *
 * Sets the `super_admin: true` custom claim on a user in the master project.
 * This enables the Firestore rules to check `request.auth.token.super_admin == true`
 * instead of reading the app_config/admin_access document, avoiding any
 * circular dependency issues.
 *
 * Requires: Caller must be an authenticated superadmin (custom claim super_admin == true)
 * Secret: SERVICE_ACCOUNT_JSON (master project service account)
 *
 * @param data.email - Email of the user to promote to superadmin
 * @returns { success, message, uid, alreadySet }
 * @throws HttpsError if not superadmin, user not found, or claim setting fails
 */
export declare const setSuperAdminClaim: import("firebase-functions/v2/https").CallableFunction<any, Promise<{
    success: boolean;
    message: string;
    uid: string;
    alreadySet: boolean;
}>, unknown>;
//# sourceMappingURL=setSuperAdminClaim.d.ts.map