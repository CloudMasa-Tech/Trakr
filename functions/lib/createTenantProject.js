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
// ─── Helper: detect an existing incomplete workspace reservation ─────────────
async function assertWorkspaceProjectIsImmutable(masterApp, workspaceId, requestedProjectId) {
    if (!workspaceId)
        return;
    const ref = masterApp.firestore().collection("workspaces").doc(workspaceId);
    const snapshot = await ref.get();
    if (!snapshot.exists)
        return;
    const data = snapshot.data() ?? {};
    const config = data.firebaseConfig;
    const storedProjectId = typeof data.firebaseProjectId === "string"
        ? data.firebaseProjectId.trim()
        : typeof config?.projectId === "string"
            ? config.projectId.trim()
            : "";
    const requested = requestedProjectId.trim();
    if (storedProjectId && requested && storedProjectId !== requested) {
        const message = `BLOCKED: attempted to overwrite firebaseProjectId for workspace ${workspaceId} ` +
            `from ${storedProjectId} to ${requested} - this would orphan a GCP project`;
        v2_1.logger.error(message, { workspaceId, oldProjectId: storedProjectId, newProjectId: requested });
        throw new https_1.HttpsError('failed-precondition', message, {
            workspaceId,
            oldProjectId: storedProjectId,
            newProjectId: requested,
            immutableProjectBinding: true,
        });
    }
}
async function findIncompleteWorkspaceByCode(masterApp, workspaceCode) {
    const normalizedCode = workspaceCode.trim().toLowerCase();
    if (!normalizedCode)
        return null;
    const snapshot = await masterApp.firestore()
        .collection("workspaces")
        .where("workspaceCode", "==", normalizedCode)
        .limit(20)
        .get();
    for (const doc of snapshot.docs) {
        const data = doc.data();
        if (data.status !== "provisioning")
            continue;
        const config = data.firebaseConfig;
        const storedProjectId = typeof data.firebaseProjectId === "string"
            ? data.firebaseProjectId.trim()
            : typeof config?.projectId === "string"
                ? config.projectId.trim()
                : "";
        if (storedProjectId) {
            return { workspaceId: doc.id, projectId: storedProjectId };
        }
    }
    return null;
}
async function findWorkspaceProjectByCode(masterApp, workspaceCode) {
    const normalizedCode = workspaceCode.trim().toLowerCase();
    if (!normalizedCode)
        return null;
    const snapshot = await masterApp.firestore()
        .collection("workspaces")
        .where("workspaceCode", "==", normalizedCode)
        .limit(20)
        .get();
    for (const doc of snapshot.docs) {
        const data = doc.data();
        const config = data.firebaseConfig;
        const projectId = typeof data.firebaseProjectId === "string"
            ? data.firebaseProjectId.trim()
            : typeof config?.projectId === "string" ? config.projectId.trim() : "";
        if (projectId)
            return { workspaceId: doc.id, projectId };
    }
    return null;
}
// ─── Helper: generate collision-free project ID ─────────────────────────────
async function generateUniqueProjectId(baseProjectId, accessToken) {
    const existing = await getProjectIfExists(baseProjectId, accessToken);
    if (!existing) {
        return { finalId: baseProjectId, alreadyExisted: false };
    }
    if (existing.state === 'ACTIVE') {
        // Project exists under our folder — it's already ours
        if (existing.parent === FOLDER_RESOURCE) {
            v2_1.logger.info('Project already exists under managed folder', { projectId: baseProjectId });
            return { finalId: baseProjectId, alreadyExisted: true };
        }
        // Collision with a project outside our folder — generate new ID with suffix
        v2_1.logger.warn('Project ID collision - generating new ID', {
            originalId: baseProjectId,
            existingParent: existing.parent,
            state: existing.state,
        });
    }
    else if (existing.state === 'DELETE_REQUESTED' || existing.state === 'DELETE_IN_PROGRESS') {
        // GCP project IDs stay reserved for 30 days after deletion (state DELETE_REQUESTED).
        // We cannot adopt them, so we must generate a new ID.
        v2_1.logger.info(`Project ID ${baseProjectId} is soft-deleted (grace period), generating a new ID`, { projectId: baseProjectId, state: existing.state });
    }
    else {
        // Any other/unknown state: be conservative and treat as unusable
        v2_1.logger.warn(`Project ID ${baseProjectId} is in unknown state (${existing.state}), treating as unusable`, { projectId: baseProjectId });
    }
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
// ─── Helper: retry with exponential backoff ──────────────────────────────────
/**
 * Retries a GCP/Firebase API call with exponential backoff if it hits a transient error.
 * GCP project creation is eventually consistent; APIs immediately after project creation
 * may reject with transient errors (e.g. FAILED_PRECONDITION) until propagation finishes.
 */
async function withRetry(projectId, stepName, operation, maxAttempts = 10) {
    let attempt = 1;
    let delayMs = 2000;
    const startTime = Date.now();
    while (true) {
        try {
            return await operation();
        }
        catch (e) {
            const errorMsg = e.message || '';
            const isTransient = errorMsg.includes('transient state') ||
                errorMsg.includes('FAILED_PRECONDITION') ||
                errorMsg.includes('HTTP 409') ||
                errorMsg.includes('has not been used') ||
                errorMsg.includes('SERVICE_DISABLED') ||
                errorMsg.includes('createWebApp HTTP 404') ||
                (errorMsg.includes('Firebase project') && errorMsg.includes('not found'));
            if (!isTransient || attempt >= maxAttempts) {
                throw e;
            }
            const elapsedSec = Math.round((Date.now() - startTime) / 1000);
            let reason = 'transient error';
            if (errorMsg.includes('has not been used') || errorMsg.includes('SERVICE_DISABLED')) {
                reason = 'Propagation delay detected (API not yet active)';
            }
            v2_1.logger.warn(`${stepName} ${reason} on ${projectId}, retrying in ${delayMs / 1000}s (attempt ${attempt}/${maxAttempts}, total elapsed ${elapsedSec}s)`, { projectId, error: errorMsg });
            await new Promise((resolve) => setTimeout(resolve, delayMs));
            attempt++;
            delayMs = Math.min(delayMs * 2, 30000); // cap at 30s
        }
    }
}
// ─── Helper: poll project until ACTIVE (eventual consistency) ────────────────
async function pollProjectActive(projectId, accessToken, maxAttempts = 15, intervalMs = 4000) {
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
        v2_1.logger.warn(`Project ${projectId} state is ${stateStr}, polling until ACTIVE (attempt ${attempt}/${maxAttempts}, total elapsed ${elapsedSec}s)`, { projectId, state: stateStr });
        if (attempt < maxAttempts) {
            await new Promise((resolve) => setTimeout(resolve, intervalMs));
        }
    }
    throw new https_1.HttpsError('internal', `Project "${projectId}" did not become ACTIVE within ${(maxAttempts * intervalMs) / 1000} seconds.`);
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
        // 409 = Firebase already enabled on this project — treat as success (idempotent)
        if (resp.status === 409 || errText.includes('ALREADY_EXISTS') || errText.includes('already')) {
            v2_1.logger.info(`Firebase is already enabled on ${projectId}, proceeding.`, { projectId });
            return;
        }
        throw new Error(`addFirebase HTTP ${resp.status}: ${errText}`);
    }
    const body = await resp.json();
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
                'identitytoolkit.googleapis.com',
            ],
        }),
    });
    if (!resp.ok) {
        const errText = await resp.text();
        // 409 = one or more services already enabled/enabling — treat as success (idempotent)
        if (resp.status === 409 || errText.includes('ALREADY_EXISTS') || errText.includes('already')) {
            v2_1.logger.info('APIs already enabled or being enabled', { projectId });
            return;
        }
        throw new Error(`batchEnable HTTP ${resp.status}: ${errText}`);
    }
    const op = await resp.json();
    const opUrl = `https://serviceusage.googleapis.com/v1/${op.name}`;
    const poll = await pollOperation(opUrl, accessToken, 40, 3000);
    if (poll.error) {
        throw new Error(`API enablement operation failed: ${poll.error}`);
    }
}
// ─── Helper: create Firestore database in Native mode (wait for completion) ─
async function createFirestoreDatabase(projectId, accessToken) {
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
            v2_1.logger.info('Firestore database already exists', { projectId });
            return;
        }
        throw new Error(`create Firestore DB HTTP ${resp.status}: ${errText}`);
    }
    const body = await resp.json();
    // The Firestore API returns a long-running operation
    if (body.name && typeof body.done === 'boolean' && !body.done) {
        const opUrl = `https://firestore.googleapis.com/v1/${body.name}`;
        const poll = await pollOperation(opUrl, accessToken, 40, 3000);
        if (poll.error) {
            throw new Error(`Firestore database creation failed: ${poll.error}`);
        }
    }
}
async function getAuthProjectConfig(projectId, accessToken) {
    const url = 'https://identitytoolkit.googleapis.com/admin/v2/projects/' + projectId + '/config';
    const resp = await fetch(url, {
        method: 'GET',
        headers: {
            'Authorization': 'Bearer ' + accessToken,
            'Content-Type': 'application/json',
        },
    });
    const bodyText = await resp.text();
    v2_1.logger.info('Auth config GET diagnostic', {
        projectId,
        status: resp.status,
        bodyText,
    });
    let config;
    if (bodyText) {
        try {
            config = JSON.parse(bodyText);
        }
        catch {
            // Keep the raw diagnostic text only.
        }
    }
    return { status: resp.status, bodyText, config };
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
async function ensureFirebaseWebApp(projectId, accessToken) {
    const listUrl = 'https://firebase.googleapis.com/v1beta1/projects/' + projectId + '/webApps?pageSize=1000';
    const listResp = await fetch(listUrl, {
        method: 'GET',
        headers: {
            'Authorization': 'Bearer ' + accessToken,
            'Content-Type': 'application/json',
        },
    });
    if (listResp.ok) {
        const listBody = await listResp.json();
        const apps = Array.isArray(listBody.apps) ? listBody.apps : [];
        let app = apps.find((candidate) => candidate.displayName === 'Default Web App');
        if (!app && apps.length > 0) {
            app = apps[0];
        }
        if (app?.appId) {
            v2_1.logger.info('Using existing Firebase Web app for auth provisioning', {
                projectId,
                appId: app.appId,
                displayName: app.displayName,
            });
            return app;
        }
    }
    else {
        const errText = await listResp.text();
        v2_1.logger.warn('Firebase web app listing failed; attempting to create a default web app', {
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
    const createBody = await createResp.json();
    if (createBody.done === true && createBody.response?.appId) {
        v2_1.logger.info('Created Firebase Web app for auth provisioning', {
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
    const app = poll.result;
    if (!app?.appId) {
        throw new Error('Firebase web app creation completed without an appId for ' + projectId + '.');
    }
    v2_1.logger.info('Created Firebase Web app for auth provisioning', {
        projectId,
        appId: app.appId,
        displayName: app.displayName,
    });
    return app;
}
async function getFirebaseWebAppConfig(projectId, appId, accessToken) {
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
    const data = await resp.json();
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
async function enableEmailPasswordAuth(projectId, accessToken) {
    const initialGet = await getAuthProjectConfig(projectId, accessToken);
    if (initialGet.status !== 200 && initialGet.status !== 404) {
        throw new Error('Auth config GET returned unexpected HTTP ' + initialGet.status + ': ' + (initialGet.bodyText || '(empty response)'));
    }
    // Resolve the number from the final project ID at the last possible moment.
    // The project ID may have changed after a collision/suffix retry, so values
    // captured during project creation are not safe for web-app provisioning.
    const finalProject = await pollProjectActive(projectId, accessToken);
    const finalProjectNumber = finalProject.projectNumber;
    v2_1.logger.info('Creating Firebase Web app for final project', {
        finalProjectId: projectId,
        projectNumber: finalProjectNumber,
    });
    const webApp = await withRetry(projectId, 'Firebase web app provisioning', () => ensureFirebaseWebApp(projectId, accessToken));
    const webAppConfig = await getFirebaseWebAppConfig(projectId, webApp.appId, accessToken);
    const missingConfigFields = [
        ['apiKey', webAppConfig.apiKey],
        ['appId', webAppConfig.appId],
        ['projectId', webAppConfig.projectId],
        ['messagingSenderId', webAppConfig.messagingSenderId],
    ].filter(([, value]) => !value);
    v2_1.logger.info('Firebase Web app config retrieved', {
        projectId,
        appId: webApp.appId,
        configProjectId: webAppConfig.projectId,
        hasApiKey: Boolean(webAppConfig.apiKey),
        hasMessagingSenderId: Boolean(webAppConfig.messagingSenderId),
        hasStorageBucket: Boolean(webAppConfig.storageBucket),
        missingConfigFields: missingConfigFields.map(([field]) => field),
    });
    if (missingConfigFields.length > 0) {
        throw new Error('Firebase Web app config is incomplete for ' + projectId + '. Missing: ' +
            missingConfigFields.map(([field]) => field).join(', '));
    }
    const provisionUrl = 'https://firebase.googleapis.com/v1alpha/firebase:provisionFirebaseApp';
    const provisionRequest = {
        appNamespace: webApp.appId,
        parent: 'projects/' + projectId,
        webInput: {},
        firebaseAuthInput: {
            emailAuthProviderMode: 'PROVIDER_ENABLED',
        },
    };
    v2_1.logger.info('Provisioning Firebase auth provider via Firebase API', {
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
    const operation = await resp.json();
    if (operation.done === true) {
        v2_1.logger.info('Email/Password auth provisioned synchronously', {
            projectId,
            appId: webApp.appId,
            response: operation.response,
        });
        return { config: webAppConfig, projectNumber: finalProjectNumber };
    }
    if (!operation.name) {
        throw new Error('firebase:provisionFirebaseApp did not return an operation name.');
    }
    const operationUrl = 'https://firebase.googleapis.com/v1beta1/' + operation.name;
    const poll = await pollOperation(operationUrl, accessToken, 40, 3000);
    if (poll.error) {
        throw new Error('firebase:provisionFirebaseApp failed: ' + poll.error);
    }
    v2_1.logger.info('Email/Password auth provisioned', {
        projectId,
        appId: webApp.appId,
        result: poll.result,
    });
    return { config: webAppConfig, projectNumber: finalProjectNumber };
}
// ─── Main callable ──────────────────────────────────────────────────────────
exports.createTenantProject = (0, https_1.onCall)({
    secrets: [firebaseAdmin_1.serviceAccountJson],
    region: 'us-central1',
    maxInstances: 5,
    memory: '512MiB',
    timeoutSeconds: 540,
}, async (request) => {
    const startTime = Date.now();
    const projectId = request.data?.projectId;
    const workspaceCode = (request.data?.workspaceCode ?? projectId).trim().toLowerCase();
    const workspaceId = request.data?.workspaceId?.trim() ?? "";
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
    // A workspace's first project binding is permanent. Check the authoritative
    // workspace document before any collision retry or GCP create call.
    await assertWorkspaceProjectIsImmutable(masterApp, workspaceId, projectId);
    const existingWorkspace = await findWorkspaceProjectByCode(masterApp, workspaceCode);
    if (existingWorkspace &&
        (!workspaceId || existingWorkspace.workspaceId !== workspaceId ||
            existingWorkspace.projectId !== projectId)) {
        v2_1.logger.error('createTenantProject: refusing project replacement for workspace code', {
            workspaceCode,
            requestedWorkspaceId: workspaceId || null,
            requestedProjectId: projectId,
            existingWorkspaceId: existingWorkspace.workspaceId,
            existingProjectId: existingWorkspace.projectId,
        });
        throw new https_1.HttpsError('already-exists', 'Workspace code "' + workspaceCode +
            '" is already bound to Firebase project "' +
            existingWorkspace.projectId +
            '". Resume that workspace instead of creating a new project.', {
            workspaceCode,
            existingWorkspaceId: existingWorkspace.workspaceId,
            existingProjectId: existingWorkspace.projectId,
            resumeRequired: true,
        });
    }
    const reservedWorkspace = await findIncompleteWorkspaceByCode(masterApp, workspaceCode);
    if (reservedWorkspace &&
        (!workspaceId || reservedWorkspace.workspaceId !== workspaceId)) {
        v2_1.logger.error('createTenantProject: refusing duplicate project allocation', {
            workspaceCode,
            requestedWorkspaceId: workspaceId || null,
            existingWorkspaceId: reservedWorkspace.workspaceId,
            existingProjectId: reservedWorkspace.projectId,
        });
        throw new https_1.HttpsError('already-exists', 'Workspace code "' + workspaceCode +
            '" already has an incomplete workspace with Firebase project "' +
            reservedWorkspace.projectId +
            '". Resume that workspace instead of creating a new project.', {
            workspaceCode,
            existingWorkspaceId: reservedWorkspace.workspaceId,
            existingProjectId: reservedWorkspace.projectId,
            resumeRequired: true,
        });
    }
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
    let firebaseConfig;
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
        let createAttempt = 0;
        const MAX_CREATE_ATTEMPTS = 5;
        while (createAttempt < MAX_CREATE_ATTEMPTS) {
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
                    if (createResponse.status === 403) {
                        v2_1.logger.error('Project creation failed with 403', { projectId: finalProjectId, error: errorText });
                        throw new https_1.HttpsError('permission-denied', `Service account lacks "Project Creator" role on folder ${TENANT_FOLDER_ID}. ` +
                            `Grant it via: gcloud resource-manager folders add-iam-policy-binding ${TENANT_FOLDER_ID} ` +
                            `--member="serviceAccount:<MASTER_SERVICE_ACCOUNT_EMAIL>" --role="roles/resourcemanager.projectCreator"`, { actionRequired: true, folderId: TENANT_FOLDER_ID });
                    }
                    // 409 = project already exists — try to adopt it instead of failing
                    if (createResponse.status === 409 || errorText.includes('already exists') || errorText.includes('ALREADY_EXISTS')) {
                        v2_1.logger.info(`Project ${finalProjectId} already exists. Attempting to verify access...`, { projectId: finalProjectId });
                        const existing = await getProjectIfExists(finalProjectId, accessToken);
                        if (existing && existing.state === 'ACTIVE' && existing.parent === FOLDER_RESOURCE) {
                            // Adopted existing project under managed folder
                            alreadyExisted = true;
                            const nameParts = existing.name.split('/');
                            projectNumber = nameParts.length > 1 ? nameParts[1] : '';
                            projectName_ = existing.name;
                            v2_1.logger.info('Adopted existing project under managed folder — all services will be verified', { projectId: finalProjectId, projectNumber });
                            break; // Exit the creation loop
                        }
                        else if (existing && existing.state === 'ACTIVE') {
                            throw new https_1.HttpsError('already-exists', `Project ID "${finalProjectId}" already exists under a different folder (${existing.parent}). ` +
                                `Choose a different project ID or delete the existing project.`, { projectId: finalProjectId, existingParent: existing.parent });
                        }
                        else if (existing) {
                            throw new https_1.HttpsError('already-exists', `Project ID "${finalProjectId}" is currently in state ${existing.state}. ` +
                                `GCP project IDs stay reserved for 30 days after deletion. Please wait 30 days or use a different project ID.`, { projectId: finalProjectId, state: existing.state });
                        }
                        else {
                            // 409 but project not visible via GET immediately. It could be propagation delay OR an orphaned collision.
                            v2_1.logger.info('Got 409 but project not found via GET — polling for 15s to check for propagation delay', { projectId: finalProjectId });
                            try {
                                const activeProj = await pollProjectActive(finalProjectId, accessToken, 4, 4000); // 4 * 4s = 16s
                                projectNumber = activeProj.projectNumber;
                                projectName_ = activeProj.name;
                                alreadyExisted = true;
                                v2_1.logger.info('Resolved via propagation delay — project became ACTIVE and is ours.', { projectId: finalProjectId });
                                break; // Exit the creation loop
                            }
                            catch (pollErr) {
                                v2_1.logger.warn(`Resolved via collision/new suffix — Project ${finalProjectId} is inaccessible after polling (likely orphaned in another folder). Generating new ID...`, { projectId: finalProjectId });
                                finalProjectId = `${projectId}-${generateRandomSuffix(SUFFIX_LENGTH)}`;
                                projectIdChanged = true;
                                createAttempt++;
                                continue; // loop again with new ID!
                            }
                        }
                    }
                    else {
                        v2_1.logger.error('Project creation failed', { projectId: finalProjectId, status: createResponse.status, error: errorText });
                        throw new https_1.HttpsError('internal', `Failed to create project: ${errorText}`);
                    }
                }
                // Only poll the creation operation if we actually submitted a create request
                // (not when we recovered from 409 and adopted an existing project)
                if (!alreadyExisted) {
                    const operation = await createResponse.json();
                    const operationUrl = `https://cloudresourcemanager.googleapis.com/v3/${operation.name}`;
                    const poll = await pollOperation(operationUrl, accessToken, 40, 3000);
                    if (poll.error) {
                        throw new https_1.HttpsError('internal', `Project creation failed: ${poll.error}`);
                    }
                    const createdProject = poll.result;
                    projectNumber = createdProject.projectNumber ?? '';
                    projectName_ = createdProject.name ?? '';
                    v2_1.logger.info('GCP project created', { projectId: finalProjectId, projectNumber });
                    break;
                }
            }
            else {
                // Project already existed — fetch its details
                v2_1.logger.info('Skipping GCP project creation — already exists', { projectId: finalProjectId });
                const existing = await getProjectIfExists(finalProjectId, accessToken);
                if (existing && existing.state === 'ACTIVE') {
                    // Extract project number from the name field (format: "projects/123456789")
                    const nameParts = existing.name.split('/');
                    projectNumber = nameParts.length > 1 ? nameParts[1] : '';
                    projectName_ = existing.name;
                    break;
                }
                else if (existing) {
                    throw new https_1.HttpsError('internal', `Cannot adopt project ${finalProjectId} because its state is ${existing.state}`);
                }
            }
        }
        if (createAttempt >= MAX_CREATE_ATTEMPTS) {
            throw new https_1.HttpsError('internal', `Failed to create project after ${MAX_CREATE_ATTEMPTS} collision retries.`);
        }
        // Wait for project to be fully ACTIVE and replicated before touching Firebase APIs.
        // This helps avoid FAILED_PRECONDITION when GCP propagation is slow.
        v2_1.logger.info('Pre-flight check: ensuring project is ACTIVE before enabling Firebase', { projectId: finalProjectId });
        await pollProjectActive(finalProjectId, accessToken);
        // ---- Step 3: Enable Firebase services (wait for completion) ----
        try {
            v2_1.logger.info('Enabling Firebase on project', { projectId: finalProjectId });
            await withRetry(finalProjectId, 'Firebase enable', () => enableFirebaseOnProject(finalProjectId, accessToken));
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
            await withRetry(finalProjectId, 'API enable', () => enableRequiredApis(finalProjectId, accessToken));
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
            await withRetry(finalProjectId, 'Firestore DB create', () => createFirestoreDatabase(finalProjectId, accessToken));
            firestoreDbCreated = true;
            v2_1.logger.info('Firestore database created', { projectId: finalProjectId });
        }
        catch (e) {
            const msg = e.message;
            v2_1.logger.error('Firestore database creation failed', { projectId: finalProjectId, error: msg });
            throw new https_1.HttpsError('internal', `Failed to create Firestore database on ${finalProjectId}: ${msg}`);
        }
        // ---- Step 6: Enable Email/Password auth provider ----
        try {
            v2_1.logger.info('Enabling Email/Password auth provider', { projectId: finalProjectId });
            const authResult = await enableEmailPasswordAuth(finalProjectId, accessToken);
            firebaseConfig = authResult.config;
            // Use the same fresh lookup that guarded web-app provisioning in the
            // response, never a number captured before a project-ID retry.
            projectNumber = authResult.projectNumber;
            authEnabled = true;
            v2_1.logger.info('Email/Password auth enabled', { projectId: finalProjectId });
        }
        catch (e) {
            const msg = e.message;
            v2_1.logger.error('Auth provider enablement failed', { projectId: finalProjectId, error: msg });
            if (msg.includes('HTTP 429') ||
                msg.includes('RATE_LIMIT_EXCEEDED') ||
                msg.includes('RESOURCE_EXHAUSTED') ||
                msg.includes('Quota exceeded')) {
                throw new https_1.HttpsError('resource-exhausted', `Firebase provisioning quota exceeded while enabling Email/Password auth on ${finalProjectId}. ` +
                    'The project, Firebase services, APIs, and Firestore database are already ready. ' +
                    'Wait at least 60 seconds before retrying; the retry will reuse this project.', {
                    retryable: true,
                    retryAfterSeconds: 60,
                    failedStep: Step.AUTH_ENABLE,
                    projectId: finalProjectId,
                });
            }
            throw new https_1.HttpsError('internal', `Failed to enable Email/Password auth on ${finalProjectId}: ${msg}`);
        }
        const durationMs = Date.now() - startTime;
        v2_1.logger.info(`createTenantProject total duration: ${Math.round(durationMs / 1000)}s`);
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
            firebaseConfig: firebaseConfig,
            durationMs,
        };
    }
    catch (error) {
        const durationMs = Date.now() - startTime;
        v2_1.logger.info(`createTenantProject total duration: ${Math.round(durationMs / 1000)}s`);
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