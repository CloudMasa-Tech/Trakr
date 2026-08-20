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
import { defineSecret } from 'firebase-functions/params';

// Define the secret parameter - this tells Firebase CLI to inject the secret
// as an environment variable at deploy time and mount it at runtime.
export const serviceAccountJson = defineSecret('SERVICE_ACCOUNT_JSON');

// Use a named app to avoid conflicts with other functions that might initialize
// the default app differently. This ensures isolation between functions.
const MASTER_APP_NAME = 'master-control-plane';

/**
 * Initialize the Admin SDK for the master/control-plane project.
 * Reads the service account JSON from the Secret Manager secret.
 * 
 * @returns The initialized admin app (or existing app if already initialized)
 * @throws HttpsError if SERVICE_ACCOUNT_JSON secret is not set or invalid
 */
export function initializeMasterAdmin(): admin.app.App {
  // Check if the named app already exists
  try {
    return admin.app(MASTER_APP_NAME);
  } catch {
    // App doesn't exist yet, continue to initialize
  }

  // The secret value is available as an environment variable at runtime
  // because defineSecret() mounts it automatically.
  const saJson = process.env.SERVICE_ACCOUNT_JSON;
  
  if (!saJson) {
    throw new Error(
      'SERVICE_ACCOUNT_JSON secret not found. ' +
      'Ensure the secret is created in Secret Manager and deployed with the function. ' +
      'Run: firebase functions:secrets:set SERVICE_ACCOUNT_JSON'
    );
  }

  let serviceAccount: admin.ServiceAccount;
  try {
    serviceAccount = JSON.parse(saJson);
  } catch (e) {
    throw new Error(`Invalid SERVICE_ACCOUNT_JSON: ${e instanceof Error ? e.message : 'not valid JSON'}`);
  }

  // Initialize a named app to avoid conflicts with other functions
  return admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  }, MASTER_APP_NAME);
}

/**
 * Get the master app instance, initializing if needed.
 */
export function getMasterAdmin(): admin.app.App {
  try {
    return admin.app(MASTER_APP_NAME);
  } catch {
    return initializeMasterAdmin();
  }
}

/**
 * Get an OAuth2 access token for the master project's service account.
 * Used for calling Firebase REST APIs (Security Rules, Firestore Admin, etc.)
 * on tenant projects where the service account has been granted IAM roles.
 */
export async function getMasterAccessToken(): Promise<string> {
  const app = getMasterAdmin();
  const credential = app.options.credential;
  
  if (!credential || typeof (credential as any).getAccessToken !== 'function') {
    throw new Error('Master credential does not support getAccessToken()');
  }
  
  const accessTokenResult = await (credential as any).getAccessToken();
  const accessToken = accessTokenResult?.access_token;
  
  if (!accessToken) {
    throw new Error('Failed to get access token from master service account');
  }
  
  return accessToken;
}