/**
 * Shared Firebase Admin SDK initialization with Secret Manager support.
 *
 * Uses firebase-functions v2 params API to read the service account JSON
 * from Google Secret Manager via defineSecret(). The secret is automatically
 * mounted as an environment variable at runtime.
 *
 * Required secret: SERVICE_ACCOUNT_JSON (contains the full service account JSON)
 */
import * as admin from 'firebase-admin';
export declare const serviceAccountJson: import("firebase-functions/lib/params/types").SecretParam;
/**
 * Initialize the Admin SDK for the master/control-plane project.
 * Reads the service account JSON from the Secret Manager secret.
 *
 * @returns The initialized admin app (or existing app if already initialized)
 * @throws HttpsError if SERVICE_ACCOUNT_JSON secret is not set or invalid
 */
export declare function initializeMasterAdmin(): admin.app.App;
/**
 * Get the master app instance, initializing if needed.
 */
export declare function getMasterAdmin(): admin.app.App;
/**
 * Get an OAuth2 access token for the master project's service account.
 * Used for calling Firebase REST APIs (Security Rules, Firestore Admin, etc.)
 * on tenant projects where the service account has been granted IAM roles.
 */
export declare function getMasterAccessToken(): Promise<string>;
//# sourceMappingURL=firebaseAdmin.d.ts.map