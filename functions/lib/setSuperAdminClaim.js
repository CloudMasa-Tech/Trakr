"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.setSuperAdminClaim = void 0;
const https_1 = require("firebase-functions/v2/https");
const v2_1 = require("firebase-functions/v2");
const firebaseAdmin_1 = require("./lib/firebaseAdmin");
exports.setSuperAdminClaim = (0, https_1.onCall)({
    secrets: [firebaseAdmin_1.serviceAccountJson],
    region: 'us-central1',
    maxInstances: 5,
    memory: '256MiB',
    timeoutSeconds: 60,
}, async (request) => {
    const email = request.data?.email;
    // ---- Auth/Authorization ----
    if (!request.auth?.token?.super_admin) {
        v2_1.logger.warn('setSuperAdminClaim: permission denied - not superadmin', {
            uid: request.auth?.uid,
            email: request.auth?.token?.email,
        });
        throw new https_1.HttpsError('permission-denied', 'Only superadmins can set superadmin claims. Missing super_admin custom claim.');
    }
    // ---- Input Validation ----
    if (!email || typeof email !== 'string') {
        throw new https_1.HttpsError('invalid-argument', 'email is required (string)');
    }
    const normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail.includes('@') || normalizedEmail.length < 5) {
        throw new https_1.HttpsError('invalid-argument', 'Invalid email format');
    }
    try {
        v2_1.logger.info('setSuperAdminClaim: setting claim', { targetEmail: normalizedEmail });
        // Initialize Admin SDK for master project (uses named app)
        const masterApp = (0, firebaseAdmin_1.initializeMasterAdmin)();
        const auth = masterApp.auth();
        // Find the user by email
        let userRecord;
        try {
            userRecord = await auth.getUserByEmail(normalizedEmail);
        }
        catch (error) {
            if (error.code === 'auth/user-not-found') {
                throw new https_1.HttpsError('not-found', `User with email ${normalizedEmail} not found in master project`);
            }
            throw error;
        }
        // Check if custom claim already set
        const currentClaims = userRecord.customClaims || {};
        if (currentClaims.super_admin === true) {
            v2_1.logger.info('Super admin claim already set', { uid: userRecord.uid, email: normalizedEmail });
            return {
                success: true,
                message: `Super admin claim already set for ${normalizedEmail}`,
                uid: userRecord.uid,
                alreadySet: true,
            };
        }
        // Set the custom claim (merge with existing claims)
        await auth.setCustomUserClaims(userRecord.uid, {
            ...currentClaims,
            super_admin: true,
        });
        v2_1.logger.info('Set super_admin claim', {
            uid: userRecord.uid,
            email: normalizedEmail,
            claims: { ...currentClaims, super_admin: true }
        });
        return {
            success: true,
            message: `Super admin claim set for ${normalizedEmail}`,
            uid: userRecord.uid,
            alreadySet: false,
        };
    }
    catch (error) {
        v2_1.logger.error('setSuperAdminClaim failed', {
            email: request.data?.email || 'unknown',
            error: error.message,
            stack: error.stack,
        });
        if (error instanceof https_1.HttpsError) {
            throw error;
        }
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        throw new https_1.HttpsError('internal', `Failed to set super admin claim: ${errorMessage}`);
    }
});
//# sourceMappingURL=setSuperAdminClaim.js.map