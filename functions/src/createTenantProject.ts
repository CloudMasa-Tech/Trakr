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
 *   6. Email/Password auth provider enablement via Identity Toolkit API
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
): Promise<{ name: string; parent: string; projectId: string; lifecycleState: string } | null> {
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
      const data = await response.json() as { name: string; parent: string; projectId: string; lifecycleState: string };
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

  // Project exists under our folder — it's already ours
  if (existing.parent === FOLDER_RESOURCE) {
    logger.info('Project already exists under managed folder', { projectId: baseProjectId });
    return { finalId: baseProjectId, alreadyExisted: true };
  }

  // Collision with a project outside our folder — generate new ID with suffix
  logger.warn('Project ID collision - generating new ID', {
    originalId: baseProjectId,
    existingParent: existing.parent,
  });

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
    throw new Error(`addFirebase HTTP ${resp.status}: ${errText}`);
  }

  const body = await resp.json() as any;

  // addFirebase may return a long-running operation or a synchronous result.
  // A long-running operation has a `name` field and `done` is false/undefined.
  if (body.name && typeof body.done === 'boolean' && !body.done) {
    const opUrl = `https://firebase.googleapis.com/v1beta1/${body.name}`;
    const poll = await pollOperation(opUrl, accessToken, 60, 5000);
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
        'firebaseauth.googleapis.com',
        'identitytoolkit.googleapis.com',
        'firebasestorage.googleapis.com',
        'cloudfunctions.googleapis.com',
        'cloudbuild.googleapis.com',
      ],
    }),
  });

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`batchEnable HTTP ${resp.status}: ${errText}`);
  }

  const op = await resp.json() as { name: string };
  const opUrl = `https://serviceusage.googleapis.com/v1/${op.name}`;
  const poll = await pollOperation(opUrl, accessToken, 60, 5000);
  if (poll.error) {
    throw new Error(`API enablement operation failed: ${poll.error}`);
  }
}

// ─── Helper: create Firestore database in Native mode (wait for completion) ─

async function createFirestoreDatabase(
  projectId: string,
  accessToken: string,
): Promise<void> {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      databaseId: '(default)',
      locationId: 'us-central',
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
    const poll = await pollOperation(opUrl, accessToken, 60, 5000);
    if (poll.error) {
      throw new Error(`Firestore database creation failed: ${poll.error}`);
    }
  }
}

// ─── Helper: enable Email/Password auth provider ────────────────────────────

async function enableEmailPasswordAuth(
  projectId: string,
  accessToken: string,
): Promise<void> {
  const url = `https://identitytoolkit.googleapis.com/v2/projects/${projectId}/config?updateMask=email.enabled`;
  const resp = await fetch(url, {
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      email: {
        enabled: true,
      },
    }),
  });

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`enable Email/Password auth HTTP ${resp.status}: ${errText}`);
  }
}

// ─── Main callable ──────────────────────────────────────────────────────────

export const createTenantProject = onCall(
  {
    secrets: [serviceAccountJson],
    region: 'us-central1',
    maxInstances: 5,
    memory: '512MiB',
    timeoutSeconds: 300,
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
          logger.error('Project creation failed', { projectId: finalProjectId, status: createResponse.status, error: errorText });
          if (createResponse.status === 403) {
            throw new HttpsError(
              'permission-denied',
              `Service account lacks "Project Creator" role on folder ${TENANT_FOLDER_ID}. ` +
              `Grant it via: gcloud resource-manager folders add-iam-policy-binding ${TENANT_FOLDER_ID} ` +
              `--member="serviceAccount:<MASTER_SERVICE_ACCOUNT_EMAIL>" --role="roles/resourcemanager.projectCreator"`,
              { actionRequired: true, folderId: TENANT_FOLDER_ID },
            );
          }
          if (createResponse.status === 409 || errorText.includes('already exists')) {
            throw new HttpsError('already-exists', `Project ID "${finalProjectId}" already exists.`, { projectId: finalProjectId });
          }
          throw new HttpsError('internal', `Failed to create project: ${errorText}`);
        }

        const operation = await createResponse.json() as { name: string };
        const operationUrl = `https://cloudresourcemanager.googleapis.com/v3/${operation.name}`;

        const poll = await pollOperation(operationUrl, accessToken, 60, 5000);
        if (poll.error) {
          throw new HttpsError('internal', `Project creation failed: ${poll.error}`);
        }

        const createdProject = poll.result;
        projectNumber = createdProject.projectNumber ?? '';
        projectName_ = createdProject.name ?? '';
        logger.info('GCP project created', { projectId: finalProjectId, projectNumber });
      } else {
        // Project already existed — fetch its details
        logger.info('Skipping GCP project creation — already exists', { projectId: finalProjectId });
        const existing = await getProjectIfExists(finalProjectId, accessToken);
        if (existing) {
          // Extract project number from the name field (format: "projects/123456789")
          const nameParts = existing.name.split('/');
          projectNumber = nameParts.length > 1 ? nameParts[1] : '';
          projectName_ = existing.name;
        }
      }

      // ---- Step 3: Enable Firebase services (wait for completion) ----
      try {
        logger.info('Enabling Firebase on project', { projectId: finalProjectId });
        await enableFirebaseOnProject(finalProjectId, accessToken);
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
        await enableRequiredApis(finalProjectId, accessToken);
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
        await createFirestoreDatabase(finalProjectId, accessToken);
        firestoreDbCreated = true;
        logger.info('Firestore database ready', { projectId: finalProjectId });
      } catch (e) {
        const msg = (e as Error).message;
        logger.error('Firestore database creation failed', { projectId: finalProjectId, error: msg });
        throw new HttpsError('internal', `Failed to create Firestore database on ${finalProjectId}: ${msg}`);
      }

      // ---- Step 6: Enable Email/Password auth provider ----
      try {
        logger.info('Enabling Email/Password auth provider', { projectId: finalProjectId });
        await enableEmailPasswordAuth(finalProjectId, accessToken);
        authEnabled = true;
        logger.info('Email/Password auth enabled', { projectId: finalProjectId });
      } catch (e) {
        const msg = (e as Error).message;
        logger.error('Auth provider enablement failed', { projectId: finalProjectId, error: msg });
        throw new HttpsError('internal', `Failed to enable Email/Password auth on ${finalProjectId}: ${msg}`);
      }

      const durationMs = Date.now() - startTime;
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
        durationMs,
      };

    } catch (error) {
      const durationMs = Date.now() - startTime;

      // Build partial status for diagnostics
      const partialStatus = {
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
