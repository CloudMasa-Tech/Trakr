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

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { serviceAccountJson, initializeMasterAdmin, getMasterAccessToken } from './lib/firebaseAdmin';

// Folder ID where tenant projects will be created
const TENANT_FOLDER_ID = '818058604638';
const FOLDER_RESOURCE = `folders/${TENANT_FOLDER_ID}`;

// Collision retry settings
const MAX_COLLISION_RETRIES = 5;
const SUFFIX_LENGTH = 8;

// GCP display name constraints
const MIN_DISPLAY_NAME_LENGTH = 4;
const MAX_DISPLAY_NAME_LENGTH = 30;
const ALLOWED_DISPLAY_NAME_CHARS = /^[a-zA-Z0-9\s\-\.\(\)]+$/;

// Provisioning step labels (returned in the response for debugging)
const Step = {
  PROJECT_CREATE: 'gcp_project_create',
  FIREBASE_ENABLE: 'firebase_enable',
  APIS_ENABLE: 'apis_enable',
  FIRESTORE_DB_CREATE: 'firestore_db_create',
  AUTH_ENABLE: 'auth_enable',
} as const;

// ─── Helper: display name derivation ────────────────────────────────────────

function deriveDisplayName(companyName: string, projectId: string): string {
  const sanitized = companyName.trim().replace(/[^a-zA-Z0-9\s\-\.\(\)]/g, '');

  if (sanitized.length >= MIN_DISPLAY_NAME_LENGTH && sanitized.length <= MAX_DISPLAY_NAME_LENGTH && ALLOWED_DISPLAY_NAME_CHARS.test(sanitized)) {
    return sanitized;
  }

  if (sanitized.length < MIN_DISPLAY_NAME_LENGTH) {
    const shortId = projectId.length > 8 ? projectId.substring(0, 8) : projectId;
    const padded = `${sanitized} ${shortId}`.trim();
    if (padded.length <= MAX_DISPLAY_NAME_LENGTH) {
      return padded;
    }
    const availableForCompany = MAX_DISPLAY_NAME_LENGTH - shortId.length - 1;
    if (availableForCompany >= MIN_DISPLAY_NAME_LENGTH) {
      return `${sanitized.substring(0, availableForCompany)} ${shortId}`.trim();
    }
    return `Project ${shortId}`.substring(0, MAX_DISPLAY_NAME_LENGTH);
  }

  if (sanitized.length > MAX_DISPLAY_NAME_LENGTH) {
    return sanitized.substring(0, MAX_DISPLAY_NAME_LENGTH);
  }

  return sanitized.substring(0, MAX_DISPLAY_NAME_LENGTH);
}

// ─── Helper: random suffix generation ───────────────────────────────────────

function generateRandomSuffix(length: number): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  const bytes: Buffer = require('crypto').randomBytes(length);
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars[bytes[i] % chars.length];
  }
  return result;
}

// ─── Helper: check if a project already exists via CRM v3 ──────────────────

async function getProjectIfExists(
  projectId: string,
  accessToken: string,
): Promise<{ name: string; parent: string; projectId: string; state: string } | null> {
  try {
    const url = `https://cloudresourcemanager.googleapis.com/v3/projects/${projectId}`;
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
    });
    if (response.ok) {
      const data = await response.json() as { name: string; parent: string; projectId: string; state: string };
      return data;
    }
    if (response.status === 403 || response.status === 404) {
      return null;
    }
    const text = await response.text();
    logger.warn('getProjectIfExists: unexpected response', { projectId, status: response.status, text });
    return null;
  } catch (e) {
    logger.warn('getProjectIfExists: error', { projectId, error: (e as Error).message });
    return null;
  }
}

// ─── Helper: generate collision-free project ID ─────────────────────────────

async function generateUniqueProjectId(
  baseProjectId: string,
  accessToken: string,
): Promise<{ finalId: string; alreadyExisted: boolean }> {
  const existing = await getProjectIfExists(baseProjectId, accessToken);
  if (!existing) {
    return { finalId: baseProjectId, alreadyExisted: false };
  }

  if (existing.state === 'ACTIVE') {
    // Project exists under our folder — it's already ours
    if (existing.parent === FOLDER_RESOURCE) {
      logger.info('Project already exists under managed folder', { projectId: baseProjectId });
      return { finalId: baseProjectId, alreadyExisted: true };
    }

    // Collision with a project outside our folder — generate new ID with suffix
    logger.warn('Project ID collision - generating new ID', {
      originalId: baseProjectId,
      existingParent: existing.parent,
      state: existing.state,
    });
  } else if (existing.state === 'DELETE_REQUESTED' || existing.state === 'DELETE_IN_PROGRESS') {
    // GCP project IDs stay reserved for 30 days after deletion (state DELETE_REQUESTED).
    // We cannot adopt them, so we must generate a new ID.
    logger.info(`Project ID ${baseProjectId} is soft-deleted (grace period), generating a new ID`, { projectId: baseProjectId, state: existing.state });
  } else {
    // Any other/unknown state: be conservative and treat as unusable
    logger.warn(`Project ID ${baseProjectId} is in unknown state (${existing.state}), treating as unusable`, { projectId: baseProjectId });
  }

  for (let attempt = 0; attempt < MAX_COLLISION_RETRIES; attempt++) {
    const suffix = generateRandomSuffix(SUFFIX_LENGTH);
    const candidateId = `${baseProjectId}-${suffix}`;

    if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(candidateId)) {
      continue;
    }

    const candidateExisting = await getProjectIfExists(candidateId, accessToken);
    if (!candidateExisting) {
      logger.info('Generated unique project ID', { originalId: baseProjectId, newId: candidateId });
      return { finalId: candidateId, alreadyExisted: false };
    }
  }

  throw new Error(
    `Could not generate unique project ID after ${MAX_COLLISION_RETRIES} attempts. ` +
    `Base ID "${baseProjectId}" and all suffixes collide with existing projects.`
  );
}

// ─── Helper: retry with exponential backoff ──────────────────────────────────

/**
 * Retries a GCP/Firebase API call with exponential backoff if it hits a transient error.
 * GCP project creation is eventually consistent; APIs immediately after project creation
 * may reject with transient errors (e.g. FAILED_PRECONDITION) until propagation finishes.
 */
async function withRetry<T>(
  projectId: string,
  stepName: string,
  operation: () => Promise<T>,
  maxAttempts = 10,
): Promise<T> {
  let attempt = 1;
  let delayMs = 2000;
  const startTime = Date.now();

  while (true) {
    try {
      return await operation();
    } catch (e) {
      const errorMsg = (e as Error).message || '';
      const isTransient = errorMsg.includes('transient state') ||
                          errorMsg.includes('FAILED_PRECONDITION') ||
                          errorMsg.includes('HTTP 409') ||
                          errorMsg.includes('has not been used') ||
                          errorMsg.includes('SERVICE_DISABLED');

      if (!isTransient || attempt >= maxAttempts) {
        throw e;
      }

      const elapsedSec = Math.round((Date.now() - startTime) / 1000);
      let reason = 'transient error';
      if (errorMsg.includes('has not been used') || errorMsg.includes('SERVICE_DISABLED')) {
        reason = 'Propagation delay detected (API not yet active)';
      }

      logger.warn(`${stepName} ${reason} on ${projectId}, retrying in ${delayMs / 1000}s (attempt ${attempt}/${maxAttempts}, total elapsed ${elapsedSec}s)`, { projectId, error: errorMsg });
      await new Promise((resolve) => setTimeout(resolve, delayMs));

      attempt++;
      delayMs = Math.min(delayMs * 2, 30000); // cap at 30s
    }
  }
}

// ─── Helper: poll project until ACTIVE (eventual consistency) ────────────────

async function pollProjectActive(
  projectId: string,
  accessToken: string,
  maxAttempts = 15,
  intervalMs = 4000,
): Promise<{ name: string; projectNumber: string }> {
  const startTime = Date.now();
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const existing = await getProjectIfExists(projectId, accessToken);
    if (existing && existing.state === 'ACTIVE') {
      const nameParts = existing.name.split('/');
      const projectNumber = nameParts.length > 1 ? nameParts[1] : '';
      return { name: existing.name, projectNumber };
    }

    const elapsedSec = Math.round((Date.now() - startTime) / 1000);
    const stateStr = existing ? existing.state : 'NOT_FOUND';
    logger.warn(`Project ${projectId} state is ${stateStr}, polling until ACTIVE (attempt ${attempt}/${maxAttempts}, total elapsed ${elapsedSec}s)`, { projectId, state: stateStr });
    
    if (attempt < maxAttempts) {
      await new Promise((resolve) => setTimeout(resolve, intervalMs));
    }
  }

  throw new HttpsError('internal', `Project "${projectId}" did not become ACTIVE within ${(maxAttempts * intervalMs) / 1000} seconds.`);
}

// ─── Helper: poll a long-running operation until done ───────────────────────

async function pollOperation(
  operationUrl: string,
  accessToken: string,
  maxAttempts = 60,
  intervalMs = 5000,
): Promise<{ done: boolean; result?: any; error?: string }> {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, intervalMs));

    const opResponse = await fetch(operationUrl, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
    });

    if (!opResponse.ok) {
      const errText = await opResponse.text();
      logger.warn('pollOperation: transient error', { operationUrl, attempt, errText });
      continue;
    }

    const body = await opResponse.json() as { done?: boolean; error?: { message?: string }; response?: any };
    if (body.done === true) {
      if (body.error) {
        return { done: true, error: body.error.message || 'Operation failed' };
      }
      return { done: true, result: body.response };
    }
  }

  return { done: false, error: `Operation timed out after ${(maxAttempts * intervalMs) / 1000}s` };
}

// ─── Helper: enable Firebase on project (wait for completion) ──────────────

async function enableFirebaseOnProject(
  projectId: string,
  accessToken: string,
): Promise<void> {
  const url = `https://firebase.googleapis.com/v1beta1/projects/${projectId}:addFirebase`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({}),
  });

  if (!resp.ok) {
    const errText = await resp.text();
    // 409 = Firebase already enabled on this project — treat as success (idempotent)
    if (resp.status === 409 || errText.includes('ALREADY_EXISTS') || errText.includes('already')) {
      logger.info(`Firebase is already enabled on ${projectId}, proceeding.`, { projectId });
      return;
    }
    throw new Error(`addFirebase HTTP ${resp.status}: ${errText}`);
  }

  const body = await resp.json() as any;

  // addFirebase may return a long-running operation or a synchronous result.
  // A long-running operation has a `name` field and `done` is false/undefined.
  if (body.name && typeof body.done === 'boolean' && !body.done) {
    const opUrl = `https://firebase.googleapis.com/v1beta1/${body.name}`;
    const poll = await pollOperation(opUrl, accessToken, 40, 3000);
    if (poll.error) {
      throw new Error(`Firebase enablement operation failed: ${poll.error}`);
    }
  }
  // Synchronous response (FirebaseProject) or already-done operation — success.
}

// ─── Helper: enable required APIs (wait for completion) ─────────────────────

async function enableRequiredApis(
  projectId: string,
  accessToken: string,
): Promise<void> {
  const url = `https://serviceusage.googleapis.com/v1/projects/${projectId}/services:batchEnable`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      serviceIds: [
        'firestore.googleapis.com',
        'identitytoolkit.googleapis.com',
      ],
    }),
  });

  if (!resp.ok) {
    const errText = await resp.text();
    // 409 = one or more services already enabled/enabling — treat as success (idempotent)
    if (resp.status === 409 || errText.includes('ALREADY_EXISTS') || errText.includes('already')) {
      logger.info('APIs already enabled or being enabled', { projectId });
      return;
    }
    throw new Error(`batchEnable HTTP ${resp.status}: ${errText}`);
  }

  const op = await resp.json() as { name: string };
  const opUrl = `https://serviceusage.googleapis.com/v1/${op.name}`;
  const poll = await pollOperation(opUrl, accessToken, 40, 3000);
  if (poll.error) {
    throw new Error(`API enablement operation failed: ${poll.error}`);
  }
}

// ─── Helper: create Firestore database in Native mode (wait for completion) ─

async function createFirestoreDatabase(
  projectId: string,
  accessToken: string,
): Promise<void> {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases?databaseId=(default)`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      locationId: 'us-central1',
      type: 'FIRESTORE_NATIVE',
    }),
  });

  if (!resp.ok) {
    const errText = await resp.text();
    // 409 = database already exists — treat as success (idempotent)
    if (resp.status === 409 || errText.includes('already exists')) {
      logger.info('Firestore database already exists', { projectId });
      return;
    }
    throw new Error(`create Firestore DB HTTP ${resp.status}: ${errText}`);
  }

  const body = await resp.json() as any;
  // The Firestore API returns a long-running operation
  if (body.name && typeof body.done === 'boolean' && !body.done) {
    const opUrl = `https://firestore.googleapis.com/v1/${body.name}`;
    const poll = await pollOperation(opUrl, accessToken, 40, 3000);
    if (poll.error) {
      throw new Error(`Firestore database creation failed: ${poll.error}`);
    }
  }
}

// ─── Helper: enable Email/Password auth provider ────────────────────────────

interface AuthProjectConfig {
  name?: string;
  signIn?: {
    email?: {
      enabled?: boolean;
      passwordRequired?: boolean;
    };
  };
}

async function getAuthProjectConfig(
  projectId: string,
  accessToken: string,
): Promise<{ status: number; bodyText: string; config?: AuthProjectConfig }> {
  const url = 'https://identitytoolkit.googleapis.com/admin/v2/projects/' + projectId + '/config';
  const resp = await fetch(url, {
    method: 'GET',
    headers: {
      'Authorization': 'Bearer ' + accessToken,
      'Content-Type': 'application/json',
    },
  });

  const bodyText = await resp.text();
  logger.info('Auth config GET diagnostic', {
    projectId,
    status: resp.status,
    bodyText,
  });

  let config: AuthProjectConfig | undefined;
  if (bodyText) {
    try {
      config = JSON.parse(bodyText) as AuthProjectConfig;
    } catch {
      // Keep the raw diagnostic text only.
    }
  }

  return { status: resp.status, bodyText, config };
}

interface FirebaseWebApp {
  appId: string;
  displayName?: string;
}

interface FirebaseWebAppConfig {
  projectId: string;
  appId: string;
  apiKey: string;
  authDomain: string;
  messagingSenderId: string;
  storageBucket: string;
  measurementId?: string;
}

/*
 * Why this exists:
 * - `identitytoolkit.googleapis.com/v2/projects/.../identityPlatform:initializeAuth`
 *   is the paid Identity Platform path. It returns BILLING_NOT_ENABLED on fresh Spark projects.
 * - The Firebase CLI's auth deploy flow traces through `firebase-tools` and uses
 *   `firebase.googleapis.com/v1alpha/firebase:provisionFirebaseApp` instead.
 * - That Firebase API call is the Spark-compatible path for enabling Email/Password auth
 *   on a brand-new Firebase project, and it must be preserved here.
 */
async function ensureFirebaseWebApp(
  projectId: string,
  accessToken: string,
): Promise<FirebaseWebApp> {
  const listUrl = 'https://firebase.googleapis.com/v1beta1/projects/' + projectId + '/webApps?pageSize=1000';
  const listResp = await fetch(listUrl, {
    method: 'GET',
    headers: {
      'Authorization': 'Bearer ' + accessToken,
      'Content-Type': 'application/json',
    },
  });

  if (listResp.ok) {
    const listBody = await listResp.json() as { apps?: FirebaseWebApp[] };
    const apps = Array.isArray(listBody.apps) ? listBody.apps : [];
    let app = apps.find((candidate) => candidate.displayName === 'Default Web App');
    if (!app && apps.length > 0) {
      app = apps[0];
    }
    if (app?.appId) {
      logger.info('Using existing Firebase Web app for auth provisioning', {
        projectId,
        appId: app.appId,
        displayName: app.displayName,
      });
      return app;
    }
  } else {
    const errText = await listResp.text();
    logger.warn('Firebase web app listing failed; attempting to create a default web app', {
      projectId,
      status: listResp.status,
      errText,
    });
  }

  const createResp = await fetch('https://firebase.googleapis.com/v1beta1/projects/' + projectId + '/webApps', {
    method: 'POST',
    headers: {
      'Authorization': 'Bearer ' + accessToken,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ displayName: 'Default Web App' }),
  });

  if (!createResp.ok) {
    const errText = await createResp.text();
    throw new Error('createWebApp HTTP ' + createResp.status + ': ' + errText);
  }

  const createBody = await createResp.json() as { name?: string; done?: boolean; response?: FirebaseWebApp };
  if (createBody.done === true && createBody.response?.appId) {
    logger.info('Created Firebase Web app for auth provisioning', {
      projectId,
      appId: createBody.response.appId,
      displayName: createBody.response.displayName,
    });
    return createBody.response;
  }

  if (!createBody.name) {
    throw new Error('createWebApp did not return an operation name or inline response.');
  }

  const operationUrl = 'https://firebase.googleapis.com/v1beta1/' + createBody.name;
  const poll = await pollOperation(operationUrl, accessToken, 40, 3000);
  if (poll.error) {
    throw new Error('Firebase web app creation failed: ' + poll.error);
  }

  const app = poll.result as FirebaseWebApp | undefined;
  if (!app?.appId) {
    throw new Error('Firebase web app creation completed without an appId for ' + projectId + '.');
  }

  logger.info('Created Firebase Web app for auth provisioning', {
    projectId,
    appId: app.appId,
    displayName: app.displayName,
  });
  return app;
}


async function getFirebaseWebAppConfig(
  projectId: string,
  appId: string,
  accessToken: string,
): Promise<FirebaseWebAppConfig> {
  const url = `https://firebase.googleapis.com/v1beta1/projects/${projectId}/webApps/${appId}/config`;
  const resp = await fetch(url, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
  });

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`getWebAppConfig HTTP ${resp.status}: ${errText}`);
  }

  const data = await resp.json() as {
    projectId?: string;
    appId?: string;
    apiKey?: string;
    authDomain?: string;
    messagingSenderId?: string;
    storageBucket?: string;
    measurementId?: string;
  };

  return {
    projectId: data.projectId ?? projectId,
    appId: data.appId ?? appId,
    apiKey: data.apiKey ?? '',
    authDomain: data.authDomain ?? '',
    messagingSenderId: data.messagingSenderId ?? '',
    storageBucket: data.storageBucket ?? '',
    measurementId: data.measurementId,
  };
}

async function enableEmailPasswordAuth(
  projectId: string,
  accessToken: string,
): Promise<FirebaseWebAppConfig> {
  const initialGet = await getAuthProjectConfig(projectId, accessToken);
  if (initialGet.status !== 200 && initialGet.status !== 404) {
    throw new Error(
      'Auth config GET returned unexpected HTTP ' + initialGet.status + ': ' + (initialGet.bodyText || '(empty response)'),
    );
  }

  const webApp = await ensureFirebaseWebApp(projectId, accessToken);
  const webAppConfig = await getFirebaseWebAppConfig(projectId, webApp.appId, accessToken);
  const provisionUrl = 'https://firebase.googleapis.com/v1alpha/firebase:provisionFirebaseApp';
  const provisionRequest = {
    appNamespace: webApp.appId,
    parent: 'projects/' + projectId,
    webInput: {},
    firebaseAuthInput: {
      emailAuthProviderMode: 'PROVIDER_ENABLED',
    },
  };

  logger.info('Provisioning Firebase auth provider via Firebase API', {
    projectId,
    appId: webApp.appId,
    request: provisionRequest,
    previousConfigStatus: initialGet.status,
  });

  const resp = await fetch(provisionUrl, {
    method: 'POST',
    headers: {
      'Authorization': 'Bearer ' + accessToken,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(provisionRequest),
  });

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error('firebase:provisionFirebaseApp HTTP ' + resp.status + ': ' + errText);
  }

  const operation = await resp.json() as { name?: string; done?: boolean; response?: any };
  if (operation.done === true) {
    logger.info('Email/Password auth provisioned synchronously', {
      projectId,
      appId: webApp.appId,
      response: operation.response,
    });
    return webAppConfig;
  }

  if (!operation.name) {
    throw new Error('firebase:provisionFirebaseApp did not return an operation name.');
  }

  const operationUrl = 'https://firebase.googleapis.com/v1beta1/' + operation.name;
  const poll = await pollOperation(operationUrl, accessToken, 40, 3000);
  if (poll.error) {
    throw new Error('firebase:provisionFirebaseApp failed: ' + poll.error);
  }

  logger.info('Email/Password auth provisioned', {
    projectId,
    appId: webApp.appId,
    result: poll.result,
  });
  return webAppConfig;
}


// ─── Main callable ──────────────────────────────────────────────────────────

export const createTenantProject = onCall(
  {
    secrets: [serviceAccountJson],
    region: 'us-central1',
    maxInstances: 5,
    memory: '512MiB',
    timeoutSeconds: 540,
  },
  async (request) => {
    const startTime = Date.now();
    const projectId = request.data?.projectId as string;
    const companyName = request.data?.companyName as string | undefined;
    const projectName = request.data?.projectName as string | undefined;
    const billingAccount = request.data?.billingAccount as string | undefined;

    // ---- Auth/Authorization ----
    if (!request.auth?.token?.super_admin) {
      logger.warn('createTenantProject: permission denied - not superadmin', {
        uid: request.auth?.uid,
        email: request.auth?.token?.email,
      });
      throw new HttpsError(
        'permission-denied',
        'Only superadmins can create tenant projects. Missing super_admin custom claim.',
      );
    }

    // ---- Input Validation ----
    if (!projectId || typeof projectId !== 'string') {
      throw new HttpsError('invalid-argument', 'projectId is required (string)');
    }
    if (!projectId.trim()) {
      throw new HttpsError('invalid-argument', 'projectId cannot be empty');
    }
    if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId)) {
      throw new HttpsError(
        'invalid-argument',
        'projectId format invalid. Must be 6-30 chars, lowercase, start with letter, end with letter/digit, only hyphens allowed',
      );
    }

    const rawCompanyName = (companyName ?? projectName ?? '').trim();
    if (!rawCompanyName) {
      throw new HttpsError('invalid-argument', 'companyName is required (string)');
    }
    if (rawCompanyName.length > 100) {
      throw new HttpsError('invalid-argument', 'companyName cannot exceed 100 characters');
    }
    if (billingAccount && typeof billingAccount !== 'string') {
      throw new HttpsError('invalid-argument', 'billingAccount must be a string if provided');
    }

    const masterApp = initializeMasterAdmin();
    const masterProjectId = masterApp.options.projectId;
    if (projectId === masterProjectId) {
      throw new HttpsError('invalid-argument', 'Cannot create tenant project with master project ID');
    }

    let finalProjectId = projectId;
    let projectIdChanged = false;
    let alreadyExisted = false;
    let firebaseEnabled = false;
    let apisEnabled = false;
    let firestoreDbCreated = false;
    let authEnabled = false;

    try {
      // ---- Step 0: Get Access Token ----
      const accessToken = await getMasterAccessToken();

      // ---- Step 1: Generate unique project ID (handles collisions) ----
      const idResult = await generateUniqueProjectId(projectId, accessToken);
      finalProjectId = idResult.finalId;
      alreadyExisted = idResult.alreadyExisted;
      projectIdChanged = finalProjectId !== projectId;

      if (projectIdChanged) {
        logger.info('Project ID was regenerated due to collision', {
          originalId: projectId,
          finalId: finalProjectId,
        });
      }

      const displayName = deriveDisplayName(rawCompanyName, finalProjectId);
      logger.info('createTenantProject: starting', { projectId: finalProjectId, companyName: rawCompanyName, displayName, alreadyExisted });

      let projectNumber = '';
      let projectName_ = '';
      let createAttempt = 0;
      const MAX_CREATE_ATTEMPTS = 5;

      while (createAttempt < MAX_CREATE_ATTEMPTS) {
        if (!alreadyExisted) {
          // ---- Step 2: Create GCP project via Cloud Resource Manager API v3 ----
          const projectCreateUrl = 'https://cloudresourcemanager.googleapis.com/v3/projects';
          const projectBody: Record<string, any> = {
            projectId: finalProjectId,
            displayName,
            parent: FOLDER_RESOURCE,
          };
          if (billingAccount && billingAccount.trim().length > 0) {
            projectBody.billingAccount = billingAccount.trim();
          }

          const createResponse = await fetch(projectCreateUrl, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
            body: JSON.stringify(projectBody),
          });

          if (!createResponse.ok) {
            const errorText = await createResponse.text();
            if (createResponse.status === 403) {
              logger.error('Project creation failed with 403', { projectId: finalProjectId, error: errorText });
              throw new HttpsError(
                'permission-denied',
                `Service account lacks "Project Creator" role on folder ${TENANT_FOLDER_ID}. ` +
                `Grant it via: gcloud resource-manager folders add-iam-policy-binding ${TENANT_FOLDER_ID} ` +
                `--member="serviceAccount:<MASTER_SERVICE_ACCOUNT_EMAIL>" --role="roles/resourcemanager.projectCreator"`,
                { actionRequired: true, folderId: TENANT_FOLDER_ID },
              );
            }
            // 409 = project already exists — try to adopt it instead of failing
            if (createResponse.status === 409 || errorText.includes('already exists') || errorText.includes('ALREADY_EXISTS')) {
              logger.info(`Project ${finalProjectId} already exists. Attempting to verify access...`, { projectId: finalProjectId });
              const existing = await getProjectIfExists(finalProjectId, accessToken);
              if (existing && existing.state === 'ACTIVE' && existing.parent === FOLDER_RESOURCE) {
                // Adopted existing project under managed folder
                alreadyExisted = true;
                const nameParts = existing.name.split('/');
                projectNumber = nameParts.length > 1 ? nameParts[1] : '';
                projectName_ = existing.name;
                logger.info('Adopted existing project under managed folder — all services will be verified', { projectId: finalProjectId, projectNumber });
                break; // Exit the creation loop
              } else if (existing && existing.state === 'ACTIVE') {
                throw new HttpsError(
                  'already-exists',
                  `Project ID "${finalProjectId}" already exists under a different folder (${existing.parent}). ` +
                  `Choose a different project ID or delete the existing project.`,
                  { projectId: finalProjectId, existingParent: existing.parent },
                );
              } else if (existing) {
                throw new HttpsError(
                  'already-exists',
                  `Project ID "${finalProjectId}" is currently in state ${existing.state}. ` +
                  `GCP project IDs stay reserved for 30 days after deletion. Please wait 30 days or use a different project ID.`,
                  { projectId: finalProjectId, state: existing.state },
                );
              } else {
                // 409 but project not visible via GET immediately. It could be propagation delay OR an orphaned collision.
                logger.info('Got 409 but project not found via GET — polling for 15s to check for propagation delay', { projectId: finalProjectId });
                try {
                  const activeProj = await pollProjectActive(finalProjectId, accessToken, 4, 4000); // 4 * 4s = 16s
                  projectNumber = activeProj.projectNumber;
                  projectName_ = activeProj.name;
                  alreadyExisted = true;
                  logger.info('Resolved via propagation delay — project became ACTIVE and is ours.', { projectId: finalProjectId });
                  break; // Exit the creation loop
                } catch (pollErr) {
                  logger.warn(`Resolved via collision/new suffix — Project ${finalProjectId} is inaccessible after polling (likely orphaned in another folder). Generating new ID...`, { projectId: finalProjectId });
                  finalProjectId = `${projectId}-${generateRandomSuffix(SUFFIX_LENGTH)}`;
                  projectIdChanged = true;
                  createAttempt++;
                  continue; // loop again with new ID!
                }
              }
            } else {
              logger.error('Project creation failed', { projectId: finalProjectId, status: createResponse.status, error: errorText });
              throw new HttpsError('internal', `Failed to create project: ${errorText}`);
            }
          }

          // Only poll the creation operation if we actually submitted a create request
          // (not when we recovered from 409 and adopted an existing project)
          if (!alreadyExisted) {
            const operation = await createResponse.json() as { name: string };
            const operationUrl = `https://cloudresourcemanager.googleapis.com/v3/${operation.name}`;

            const poll = await pollOperation(operationUrl, accessToken, 40, 3000);
            if (poll.error) {
              throw new HttpsError('internal', `Project creation failed: ${poll.error}`);
            }

            const createdProject = poll.result;
            projectNumber = createdProject.projectNumber ?? '';
            projectName_ = createdProject.name ?? '';
            logger.info('GCP project created', { projectId: finalProjectId, projectNumber });
            break;
          }
        } else {
          // Project already existed — fetch its details
          logger.info('Skipping GCP project creation — already exists', { projectId: finalProjectId });
          const existing = await getProjectIfExists(finalProjectId, accessToken);
          if (existing && existing.state === 'ACTIVE') {
            // Extract project number from the name field (format: "projects/123456789")
            const nameParts = existing.name.split('/');
            projectNumber = nameParts.length > 1 ? nameParts[1] : '';
            projectName_ = existing.name;
            break;
          } else if (existing) {
             throw new HttpsError('internal', `Cannot adopt project ${finalProjectId} because its state is ${existing.state}`);
          }
        }
      }

      if (createAttempt >= MAX_CREATE_ATTEMPTS) {
        throw new HttpsError('internal', `Failed to create project after ${MAX_CREATE_ATTEMPTS} collision retries.`);
      }

      // Wait for project to be fully ACTIVE and replicated before touching Firebase APIs.
      // This helps avoid FAILED_PRECONDITION when GCP propagation is slow.
      logger.info('Pre-flight check: ensuring project is ACTIVE before enabling Firebase', { projectId: finalProjectId });
      await pollProjectActive(finalProjectId, accessToken);

      // ---- Step 3: Enable Firebase services (wait for completion) ----
      try {
        logger.info('Enabling Firebase on project', { projectId: finalProjectId });
        await withRetry(finalProjectId, 'Firebase enable', () => enableFirebaseOnProject(finalProjectId, accessToken));
        firebaseEnabled = true;
        logger.info('Firebase enabled', { projectId: finalProjectId });
      } catch (e) {
        const msg = (e as Error).message;
        logger.error('Firebase enablement failed', { projectId: finalProjectId, error: msg });
        throw new HttpsError('internal', `Failed to enable Firebase on project ${finalProjectId}: ${msg}`);
      }

      // ---- Step 4: Enable required APIs (wait for completion) ----
      try {
        logger.info('Enabling required APIs', { projectId: finalProjectId });
        await withRetry(finalProjectId, 'API enable', () => enableRequiredApis(finalProjectId, accessToken));
        apisEnabled = true;
        logger.info('Required APIs enabled', { projectId: finalProjectId });
      } catch (e) {
        const msg = (e as Error).message;
        logger.error('API enablement failed', { projectId: finalProjectId, error: msg });
        throw new HttpsError('internal', `Failed to enable required APIs on ${finalProjectId}: ${msg}`);
      }

      // ---- Step 5: Create Firestore database in Native mode (wait for completion) ----
      try {
        logger.info('Creating Firestore database', { projectId: finalProjectId });
        await withRetry(finalProjectId, 'Firestore DB create', () => createFirestoreDatabase(finalProjectId, accessToken));
        firestoreDbCreated = true;
        logger.info('Firestore database created', { projectId: finalProjectId });
      } catch (e) {
        const msg = (e as Error).message;
        logger.error('Firestore database creation failed', { projectId: finalProjectId, error: msg });
        throw new HttpsError('internal', `Failed to create Firestore database on ${finalProjectId}: ${msg}`);
      }

      // ---- Step 6: Enable Email/Password auth provider ----
      try {
        logger.info('Enabling Email/Password auth provider', { projectId: finalProjectId });
        const firebaseConfig = await enableEmailPasswordAuth(finalProjectId, accessToken);
        authEnabled = true;
        logger.info('Email/Password auth enabled', { projectId: finalProjectId });
      } catch (e) {
        const msg = (e as Error).message;
        logger.error('Auth provider enablement failed', { projectId: finalProjectId, error: msg });
        throw new HttpsError('internal', `Failed to enable Email/Password auth on ${finalProjectId}: ${msg}`);
      }

      const durationMs = Date.now() - startTime;
      logger.info(`createTenantProject total duration: ${Math.round(durationMs / 1000)}s`);
      logger.info('createTenantProject completed successfully', {
        projectId: finalProjectId,
        projectNumber,
        alreadyExisted,
        durationMs,
      });

      return {
        success: true,
        message: alreadyExisted
          ? `Project ${finalProjectId} already existed under folder ${TENANT_FOLDER_ID} (all services verified)`
          : projectIdChanged
            ? `Project ${finalProjectId} created successfully under folder ${TENANT_FOLDER_ID} (original "${projectId}" was taken)`
            : `Project ${finalProjectId} created and fully provisioned under folder ${TENANT_FOLDER_ID}`,
        projectId: finalProjectId,
        projectNumber,
        projectName: rawCompanyName,
        displayName,
        folderId: TENANT_FOLDER_ID,
        projectIdChanged,
        originalProjectId: projectIdChanged ? projectId : undefined,
        alreadyExisted,
        firebaseEnabled,
        apisEnabled,
        firestoreDbCreated,
        authEnabled,
        firebaseConfig: firebaseConfig,
        durationMs,
      };

    } catch (error) {
      const durationMs = Date.now() - startTime;
      logger.info(`createTenantProject total duration: ${Math.round(durationMs / 1000)}s`);

      // Build partial status for diagnostics
      const partialStatus = {
        alreadyExisted,
        firebaseEnabled,
        apisEnabled,
        firestoreDbCreated,
        authEnabled,
        failedStep: !firebaseEnabled
          ? Step.FIREBASE_ENABLE
          : !apisEnabled
            ? Step.APIS_ENABLE
            : !firestoreDbCreated
              ? Step.FIRESTORE_DB_CREATE
              : !authEnabled
                ? Step.AUTH_ENABLE
                : 'unknown',
      };

      logger.error('createTenantProject failed', {
        projectId,
        finalProjectId,
        durationMs,
        partialStatus,
        error: (error as Error).message,
        stack: (error as Error).stack,
      });

      if (error instanceof HttpsError) {
        // Attach partial status to the error details for the caller
        throw new HttpsError(
          error.code,
          error.message,
          { ...((error as any).details || {}), ...partialStatus },
        );
      }

      const errorMessage = error instanceof Error ? error.message : 'Unknown error';

      if (errorMessage.includes('PERMISSION_DENIED') || errorMessage.includes('permission-denied')) {
        throw new HttpsError(
          'permission-denied',
          `Service account lacks required IAM roles on folder ${TENANT_FOLDER_ID}. ` +
          `Original error: ${errorMessage}`,
          { actionRequired: true, folderId: TENANT_FOLDER_ID, ...partialStatus },
        );
      }

      throw new HttpsError('internal', `Project provisioning failed: ${errorMessage}`, partialStatus);
    }
  },
);
