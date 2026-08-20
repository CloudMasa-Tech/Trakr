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

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { serviceAccountJson, initializeMasterAdmin } from './lib/firebaseAdmin';

export const setSuperAdminClaim = onCall(
  {
    secrets: [serviceAccountJson],
    region: 'us-central1',
    maxInstances: 5,
    memory: '256MiB',
    timeoutSeconds: 60,
  },
  async (request) => {
    const email = request.data?.email as string | undefined;
    
    // ---- Auth/Authorization ----
    if (!request.auth?.token?.super_admin) {
      logger.warn('setSuperAdminClaim: permission denied - not superadmin', {
        uid: request.auth?.uid,
        email: request.auth?.token?.email,
      });
      throw new HttpsError(
        'permission-denied',
        'Only superadmins can set superadmin claims. Missing super_admin custom claim.'
      );
    }

    // ---- Input Validation ----
    if (!email || typeof email !== 'string') {
      throw new HttpsError('invalid-argument', 'email is required (string)');
    }
    
    const normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail.includes('@') || normalizedEmail.length < 5) {
      throw new HttpsError('invalid-argument', 'Invalid email format');
    }

    try {
      logger.info('setSuperAdminClaim: setting claim', { targetEmail: normalizedEmail });

      // Initialize Admin SDK for master project (uses named app)
      const masterApp = initializeMasterAdmin();
      const auth = masterApp.auth();

      // Find the user by email
      let userRecord: admin.auth.UserRecord;
      try {
        userRecord = await auth.getUserByEmail(normalizedEmail);
      } catch (error: any) {
        if (error.code === 'auth/user-not-found') {
          throw new HttpsError('not-found', `User with email ${normalizedEmail} not found in master project`);
        }
        throw error;
      }

      // Check if custom claim already set
      const currentClaims = userRecord.customClaims || {};
      if (currentClaims.super_admin === true) {
        logger.info('Super admin claim already set', { uid: userRecord.uid, email: normalizedEmail });
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

      logger.info('Set super_admin claim', { 
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

    } catch (error) {
      logger.error('setSuperAdminClaim failed', { 
        email: (request.data?.email as string) || 'unknown',
        error: (error as Error).message,
        stack: (error as Error).stack,
      });
      
      if (error instanceof HttpsError) {
        throw error;
      }
      
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      throw new HttpsError('internal', `Failed to set super admin claim: ${errorMessage}`);
    }
  }
);