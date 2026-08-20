"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.createTenantProject = void 0;
const https_1 = require("firebase-functions/v2/https");
const v2_1 = require("firebase-functions/v2");
const firebaseAdmin_1 = require("./lib/firebaseAdmin");
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
};
// ─── Helper: display name derivation ────────────────────────────────────────
function deriveDisplayName(companyName, projectId) {
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
function generateRandomSuffix(length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    const bytes = require('crypto').randomBytes(length);
    let result = '';
    for (let i = 0; i < length; i++) {
        result += chars[bytes[i] % chars.length];
    }
    return result;
}
// ─── Helper: check if a project already exists via CRM v3 ──────────────────
async function getProjectIfExists(projectId, accessToken) {
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
            const data = await response.json();
            return data;
        }
        if (response.status === 403 || response.status === 404) {
            return null;
        }
        const text = await response.text();
        v2_1.logger.warn('getProjectIfExists: unexpected response', { projectId, status: response.status, text });
        return null;
    }
    catch (e) {
        v2_1.logger.warn('getProjectIfExists: error', { projectId, error: e.message });
        return null;
    }
}
// ─── Helper: generate collision-free project ID ─────────────────────────────
async function generateUniqueProjectId(baseProjectId, accessToken) {
    const existing = await getProjectIfExists(baseProjectId, accessToken);
    if (!existing) {
        return { finalId: baseProjectId, alreadyExisted: false };
    }
    // Project exists under our folder — it's already ours
    if (existing.parent === FOLDER_RESOURCE) {
        v2_1.logger.info('Project already exists under managed folder', { projectId: baseProjectId });
        return { finalId: baseProjectId, alreadyExisted: true };
    }
    // Collision with a project outside our folder — generate new ID with suffix
    v2_1.logger.warn('Project ID collision - generating new ID', {
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
            v2_1.logger.info('Generated unique project ID', { originalId: baseProjectId, newId: candidateId });
            return { finalId: candidateId, alreadyExisted: false };
        }
    }
    throw new Error(`Could not generate unique project ID after ${MAX_COLLISION_RETRIES} attempts. ` +
        `Base ID "${baseProjectId}" and all suffixes collide with existing projects.`);
}
// ─── Helper: poll a long-running operation until done ───────────────────────
async function pollOperation(operationUrl, accessToken, maxAttempts = 60, intervalMs = 5000) {
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
            v2_1.logger.warn('pollOperation: transient error', { operationUrl, attempt, errText });
            continue;
        }
        const body = await opResponse.json();
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
async function enableFirebaseOnProject(projectId, accessToken) {
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
    const body = await resp.json();
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
async function enableRequiredApis(projectId, accessToken) {
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
    const op = await resp.json();
    const opUrl = `https://serviceusage.googleapis.com/v1/${op.name}`;
    const poll = await pollOperation(opUrl, accessToken, 60, 5000);
    if (poll.error) {
        throw new Error(`API enablement operation failed: ${poll.error}`);
    }
}
// ─── Helper: create Firestore database in Native mode (wait for completion) ─
async function createFirestoreDatabase(projectId, accessToken) {
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
            v2_1.logger.info('Firestore database already exists', { projectId });
            return;
        }
        throw new Error(`create Firestore DB HTTP ${resp.status}: ${errText}`);
    }
    const body = await resp.json();
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
async function enableEmailPasswordAuth(projectId, accessToken) {
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
exports.createTenantProject = (0, https_1.onCall)({
    secrets: [firebaseAdmin_1.serviceAccountJson],
    region: 'us-central1',
    maxInstances: 5,
    memory: '512MiB',
    timeoutSeconds: 300,
}, async (request) => {
    const startTime = Date.now();
    const projectId = request.data?.projectId;
    const companyName = request.data?.companyName;
    const projectName = request.data?.projectName;
    const billingAccount = request.data?.billingAccount;
    // ---- Auth/Authorization ----
    if (!request.auth?.token?.super_admin) {
        v2_1.logger.warn('createTenantProject: permission denied - not superadmin', {
            uid: request.auth?.uid,
            email: request.auth?.token?.email,
        });
        throw new https_1.HttpsError('permission-denied', 'Only superadmins can create tenant projects. Missing super_admin custom claim.');
    }
    // ---- Input Validation ----
    if (!projectId || typeof projectId !== 'string') {
        throw new https_1.HttpsError('invalid-argument', 'projectId is required (string)');
    }
    if (!projectId.trim()) {
        throw new https_1.HttpsError('invalid-argument', 'projectId cannot be empty');
    }
    if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId)) {
        throw new https_1.HttpsError('invalid-argument', 'projectId format invalid. Must be 6-30 chars, lowercase, start with letter, end with letter/digit, only hyphens allowed');
    }
    const rawCompanyName = (companyName ?? projectName ?? '').trim();
    if (!rawCompanyName) {
        throw new https_1.HttpsError('invalid-argument', 'companyName is required (string)');
    }
    if (rawCompanyName.length > 100) {
        throw new https_1.HttpsError('invalid-argument', 'companyName cannot exceed 100 characters');
    }
    if (billingAccount && typeof billingAccount !== 'string') {
        throw new https_1.HttpsError('invalid-argument', 'billingAccount must be a string if provided');
    }
    const masterApp = (0, firebaseAdmin_1.initializeMasterAdmin)();
    const masterProjectId = masterApp.options.projectId;
    if (projectId === masterProjectId) {
        throw new https_1.HttpsError('invalid-argument', 'Cannot create tenant project with master project ID');
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
        const accessToken = await (0, firebaseAdmin_1.getMasterAccessToken)();
        // ---- Step 1: Generate unique project ID (handles collisions) ----
        const idResult = await generateUniqueProjectId(projectId, accessToken);
        finalProjectId = idResult.finalId;
        alreadyExisted = idResult.alreadyExisted;
        projectIdChanged = finalProjectId !== projectId;
        if (projectIdChanged) {
            v2_1.logger.info('Project ID was regenerated due to collision', {
                originalId: projectId,
                finalId: finalProjectId,
            });
        }
        const displayName = deriveDisplayName(rawCompanyName, finalProjectId);
        v2_1.logger.info('createTenantProject: starting', { projectId: finalProjectId, companyName: rawCompanyName, displayName, alreadyExisted });
        let projectNumber = '';
        let projectName_ = '';
        if (!alreadyExisted) {
            // ---- Step 2: Create GCP project via Cloud Resource Manager API v3 ----
            const projectCreateUrl = 'https://cloudresourcemanager.googleapis.com/v3/projects';
            const projectBody = {
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
                v2_1.logger.error('Project creation failed', { projectId: finalProjectId, status: createResponse.status, error: errorText });
                if (createResponse.status === 403) {
                    throw new https_1.HttpsError('permission-denied', `Service account lacks "Project Creator" role on folder ${TENANT_FOLDER_ID}. ` +
                        `Grant it via: gcloud resource-manager folders add-iam-policy-binding ${TENANT_FOLDER_ID} ` +
                        `--member="serviceAccount:<MASTER_SERVICE_ACCOUNT_EMAIL>" --role="roles/resourcemanager.projectCreator"`, { actionRequired: true, folderId: TENANT_FOLDER_ID });
                }
                if (createResponse.status === 409 || errorText.includes('already exists')) {
                    throw new https_1.HttpsError('already-exists', `Project ID "${finalProjectId}" already exists.`, { projectId: finalProjectId });
                }
                throw new https_1.HttpsError('internal', `Failed to create project: ${errorText}`);
            }
            const operation = await createResponse.json();
            const operationUrl = `https://cloudresourcemanager.googleapis.com/v3/${operation.name}`;
            const poll = await pollOperation(operationUrl, accessToken, 60, 5000);
            if (poll.error) {
                throw new https_1.HttpsError('internal', `Project creation failed: ${poll.error}`);
            }
            const createdProject = poll.result;
            projectNumber = createdProject.projectNumber ?? '';
            projectName_ = createdProject.name ?? '';
            v2_1.logger.info('GCP project created', { projectId: finalProjectId, projectNumber });
        }
        else {
            // Project already existed — fetch its details
            v2_1.logger.info('Skipping GCP project creation — already exists', { projectId: finalProjectId });
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
            v2_1.logger.info('Enabling Firebase on project', { projectId: finalProjectId });
            await enableFirebaseOnProject(finalProjectId, accessToken);
            firebaseEnabled = true;
            v2_1.logger.info('Firebase enabled', { projectId: finalProjectId });
        }
        catch (e) {
            const msg = e.message;
            v2_1.logger.error('Firebase enablement failed', { projectId: finalProjectId, error: msg });
            throw new https_1.HttpsError('internal', `Failed to enable Firebase on project ${finalProjectId}: ${msg}`);
        }
        // ---- Step 4: Enable required APIs (wait for completion) ----
        try {
            v2_1.logger.info('Enabling required APIs', { projectId: finalProjectId });
            await enableRequiredApis(finalProjectId, accessToken);
            apisEnabled = true;
            v2_1.logger.info('Required APIs enabled', { projectId: finalProjectId });
        }
        catch (e) {
            const msg = e.message;
            v2_1.logger.error('API enablement failed', { projectId: finalProjectId, error: msg });
            throw new https_1.HttpsError('internal', `Failed to enable required APIs on ${finalProjectId}: ${msg}`);
        }
        // ---- Step 5: Create Firestore database in Native mode (wait for completion) ----
        try {
            v2_1.logger.info('Creating Firestore database', { projectId: finalProjectId });
            await createFirestoreDatabase(finalProjectId, accessToken);
            firestoreDbCreated = true;
            v2_1.logger.info('Firestore database ready', { projectId: finalProjectId });
        }
        catch (e) {
            const msg = e.message;
            v2_1.logger.error('Firestore database creation failed', { projectId: finalProjectId, error: msg });
            throw new https_1.HttpsError('internal', `Failed to create Firestore database on ${finalProjectId}: ${msg}`);
        }
        // ---- Step 6: Enable Email/Password auth provider ----
        try {
            v2_1.logger.info('Enabling Email/Password auth provider', { projectId: finalProjectId });
            await enableEmailPasswordAuth(finalProjectId, accessToken);
            authEnabled = true;
            v2_1.logger.info('Email/Password auth enabled', { projectId: finalProjectId });
        }
        catch (e) {
            const msg = e.message;
            v2_1.logger.error('Auth provider enablement failed', { projectId: finalProjectId, error: msg });
            throw new https_1.HttpsError('internal', `Failed to enable Email/Password auth on ${finalProjectId}: ${msg}`);
        }
        const durationMs = Date.now() - startTime;
        v2_1.logger.info('createTenantProject completed successfully', {
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
    }
    catch (error) {
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
        v2_1.logger.error('createTenantProject failed', {
            projectId,
            finalProjectId,
            durationMs,
            partialStatus,
            error: error.message,
            stack: error.stack,
        });
        if (error instanceof https_1.HttpsError) {
            // Attach partial status to the error details for the caller
            throw new https_1.HttpsError(error.code, error.message, { ...(error.details || {}), ...partialStatus });
        }
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        if (errorMessage.includes('PERMISSION_DENIED') || errorMessage.includes('permission-denied')) {
            throw new https_1.HttpsError('permission-denied', `Service account lacks required IAM roles on folder ${TENANT_FOLDER_ID}. ` +
                `Original error: ${errorMessage}`, { actionRequired: true, folderId: TENANT_FOLDER_ID, ...partialStatus });
        }
        throw new https_1.HttpsError('internal', `Project provisioning failed: ${errorMessage}`, partialStatus);
    }
});
//# sourceMappingURL=createTenantProject.js.map