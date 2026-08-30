"use strict";
/**
 * Shared Firebase Admin SDK initialization with Secret Manager support.
 *
 * Uses firebase-functions v2 params API to read the service account JSON
 * from Google Secret Manager via defineSecret(). The secret is automatically
 * mounted as an environment variable at runtime.
 *
 * Required secret: SERVICE_ACCOUNT_JSON (contains the full service account JSON)
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.serviceAccountJson = void 0;
exports.initializeMasterAdmin = initializeMasterAdmin;
exports.getMasterAdmin = getMasterAdmin;
exports.getMasterAccessToken = getMasterAccessToken;
exports.getTenantAdminApp = getTenantAdminApp;
const admin = __importStar(require("firebase-admin"));
const params_1 = require("firebase-functions/params");
// Define the secret parameter - this tells Firebase CLI to inject the secret
// as an environment variable at deploy time and mount it at runtime.
exports.serviceAccountJson = (0, params_1.defineSecret)('SERVICE_ACCOUNT_JSON');
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
function initializeMasterAdmin() {
    // Check if the named app already exists
    try {
        return admin.app(MASTER_APP_NAME);
    }
    catch {
        // App doesn't exist yet, continue to initialize
    }
    // The secret value is available as an environment variable at runtime
    // because defineSecret() mounts it automatically.
    const saJson = process.env.SERVICE_ACCOUNT_JSON;
    if (!saJson) {
        throw new Error('SERVICE_ACCOUNT_JSON secret not found. ' +
            'Ensure the secret is created in Secret Manager and deployed with the function. ' +
            'Run: firebase functions:secrets:set SERVICE_ACCOUNT_JSON');
    }
    let serviceAccount;
    try {
        serviceAccount = JSON.parse(saJson);
    }
    catch (e) {
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
function getMasterAdmin() {
    try {
        return admin.app(MASTER_APP_NAME);
    }
    catch {
        return initializeMasterAdmin();
    }
}
/**
 * Get an OAuth2 access token for the master project's service account.
 * Used for calling Firebase REST APIs (Security Rules, Firestore Admin, etc.)
 * on tenant projects where the service account has been granted IAM roles.
 */
async function getMasterAccessToken() {
    const app = getMasterAdmin();
    const credential = app.options.credential;
    if (!credential || typeof credential.getAccessToken !== 'function') {
        throw new Error('Master credential does not support getAccessToken()');
    }
    const accessTokenResult = await credential.getAccessToken();
    const accessToken = accessTokenResult?.access_token;
    if (!accessToken) {
        throw new Error('Failed to get access token from master service account');
    }
    return accessToken;
}
/**
 * Resolves/creates an Admin SDK app scoped to a TENANT project, using the
 * master service account as the credential but overriding `projectId` so every
 * Admin call targets the tenant's own Firebase project.
 *
 * The master service account must hold the appropriate IAM role on the tenant
 * project for the operation being performed (auth updates/delete for
 * `roles/firebaseauth.admin`, Firestore admin for `roles/datastore.*`, etc.).
 *
 * Apps are cached per project id so repeated invocations reuse the same
 * instance (firebase-admin forbids duplicate app names).
 */
function getTenantAdminApp(projectId) {
    const name = `tenant-adminsdk-${projectId}`;
    try {
        return admin.app(name);
    }
    catch {
        // App not initialized yet — create it below.
    }
    const saJson = process.env.SERVICE_ACCOUNT_JSON;
    if (!saJson) {
        throw new Error('SERVICE_ACCOUNT_JSON secret not found. ' +
            'Run: firebase functions:secrets:set SERVICE_ACCOUNT_JSON');
    }
    let serviceAccount;
    try {
        serviceAccount = JSON.parse(saJson);
    }
    catch (e) {
        throw new Error(`Invalid SERVICE_ACCOUNT_JSON: ${e instanceof Error ? e.message : 'not valid JSON'}`);
    }
    return admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId,
    }, name);
}
//# sourceMappingURL=firebaseAdmin.js.map