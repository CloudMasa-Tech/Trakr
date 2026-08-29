"use strict";
/**
 * HTTP Cloud Function: deployTenantRules (onRequest)
 *
 * Deploys Firestore rules and indexes to a tenant project programmatically
 * using the Firebase Admin SDK and Security Rules REST API.
 *
 * Invoked by the Flutter app during tenant provisioning after the tenant
 * Firebase project is verified but before admin onboarding begins.
 *
 * NOTE: Converted from onCall to onRequest because the Flutter Web client
 * invokes this endpoint via raw fetch/http.post with an EXPLICIT
 * `Authorization: Bearer <idToken>` header (the callable SDK was observed
 * sending empty Authorization headers). Auth is therefore verified manually
 * via admin.auth().verifyIdToken() + super_admin claim check.
 *
 * Request body: {"data": {"tenantProjectId": "..."}} (callable envelope kept
 * for compatibility; a flat body is also accepted).
 * Response body: {"result": {...}} on success, {"error": {...}} on failure.
 *
 * Requires: Caller must be an authenticated superadmin (custom claim super_admin == true)
 * Secret: SERVICE_ACCOUNT_JSON (master project service account with IAM roles on tenant project)
 *
 * IAM roles required on TENANT project for the master service account:
 * - roles/firebaserules.admin (deploy rules)
 * - roles/datastore.indexAdmin (deploy indexes)
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.deployTenantRules = void 0;
const https_1 = require("firebase-functions/v2/https");
const v2_1 = require("firebase-functions/v2");
const firebaseAdmin_1 = require("./lib/firebaseAdmin");
const httpAuth_1 = require("./lib/httpAuth");
async function handleDeployTenantRules(data) {
    const startTime = Date.now();
    const tenantProjectId = data.tenantProjectId;
    // ---- Input Validation ----
    if (!tenantProjectId || typeof tenantProjectId !== 'string') {
        throw new https_1.HttpsError('invalid-argument', 'tenantProjectId is required (string)');
    }
    if (tenantProjectId.trim().length === 0) {
        throw new https_1.HttpsError('invalid-argument', 'tenantProjectId cannot be empty');
    }
    if (!/^[a-z0-9-]{6,30}$/.test(tenantProjectId)) {
        throw new https_1.HttpsError('invalid-argument', 'tenantProjectId format invalid (expected Firebase project ID pattern)');
    }
    // Prevent deploying to master project
    const masterApp = (0, firebaseAdmin_1.initializeMasterAdmin)();
    const masterProjectId = masterApp.options.projectId;
    if (tenantProjectId === masterProjectId) {
        throw new https_1.HttpsError('invalid-argument', 'Cannot deploy tenant rules to the master/control-plane project');
    }
    try {
        v2_1.logger.info('deployTenantRules: starting deployment', { tenantProjectId });
        // ---- Get OAuth2 Access Token ----
        const accessToken = await (0, firebaseAdmin_1.getMasterAccessToken)();
        // ---- Fetch Active Ruleset from Master Project ----
        v2_1.logger.info('Fetching live rules from master project', { masterProjectId });
        const masterReleaseRes = await fetch(`https://firebaserules.googleapis.com/v1/projects/${masterProjectId}/releases/cloud.firestore`, {
            headers: { Authorization: `Bearer ${accessToken}` }
        });
        if (!masterReleaseRes.ok) {
            const errText = await masterReleaseRes.text();
            throw new Error(`Failed to fetch master project release: HTTP ${masterReleaseRes.status} ${errText}`);
        }
        const masterRelease = await masterReleaseRes.json();
        const masterRulesetName = masterRelease.rulesetName;
        if (!masterRulesetName) {
            throw new Error('Master project cloud.firestore release has no rulesetName');
        }
        const masterRulesetRes = await fetch(`https://firebaserules.googleapis.com/v1/${masterRulesetName}`, {
            headers: { Authorization: `Bearer ${accessToken}` }
        });
        if (!masterRulesetRes.ok) {
            const errText = await masterRulesetRes.text();
            throw new Error(`Failed to fetch master project ruleset ${masterRulesetName}: HTTP ${masterRulesetRes.status} ${errText}`);
        }
        const masterRuleset = await masterRulesetRes.json();
        let rulesContent = '';
        if (masterRuleset.source && masterRuleset.source.files && masterRuleset.source.files.length > 0) {
            rulesContent = masterRuleset.source.files[0].content;
        }
        if (!rulesContent) {
            throw new Error(`Master ruleset ${masterRulesetName} is empty or missing source.files content`);
        }
        v2_1.logger.info('deployTenantRules: Master rules fetched successfully', {
            masterRulesetName,
            rulesSize: rulesContent.length,
        });
        // ---- Load Indexes from bundled assets ----
        const fs = require('fs');
        const path = require('path');
        const assetsDir = path.join(__dirname, 'assets');
        const indexesPath = path.join(assetsDir, 'firestore.indexes.json');
        if (!fs.existsSync(indexesPath)) {
            throw new Error(`firestore.indexes.json not found at ${indexesPath}. ` +
                `Ensure the prebuild script (npm run prebuild) ran before tsc.`);
        }
        const indexesContent = JSON.parse(fs.readFileSync(indexesPath, 'utf8'));
        // ---- Step 1: Create Ruleset ----
        const rulesetUrl = `https://firebaserules.googleapis.com/v1/projects/${tenantProjectId}/rulesets`;
        const rulesetResponse = await fetch(`https://firebaserules.googleapis.com/v1/projects/${tenantProjectId}/rulesets`, {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                source: {
                    files: [{ name: 'firestore.rules', content: rulesContent }],
                },
            }),
        });
        if (!rulesetResponse.ok) {
            const errorText = await rulesetResponse.text();
            v2_1.logger.error('Ruleset creation failed', { tenantProjectId, status: rulesetResponse.status, error: errorText });
            // Check for permission errors
            const isPermissionDenied = errorText.includes('PERMISSION_DENIED') ||
                errorText.includes('permission-denied') ||
                rulesetResponse.status === 403;
            if (isPermissionDenied) {
                throw new https_1.HttpsError('permission-denied', `Service account lacks "Firebase Rules Admin" role on tenant project ${tenantProjectId}. ` +
                    `Grant it via: gcloud projects add-iam-policy-binding ${tenantProjectId} ` +
                    `--member="serviceAccount:<MASTER_SERVICE_ACCOUNT_EMAIL>" --role="roles/firebaserules.admin"`, { actionRequired: true, tenantProjectId });
            }
            throw new https_1.HttpsError('internal', `deployTenantRules ruleset creation failed for ${tenantProjectId}: HTTP ${rulesetResponse.status}: ${errorText}`, { operation: 'ruleset creation', tenantProjectId, status: rulesetResponse.status, response: errorText });
        }
        const ruleset = await rulesetResponse.json();
        const rulesetName = ruleset.name;
        v2_1.logger.info('Created ruleset', { tenantProjectId, rulesetName });
        // ---- Step 2: Point the cloud.firestore Release at the new Ruleset ----
        // Per projects.releases.patch docs, the body must be an
        // UpdateReleaseRequest: { "release": <full Release>, "updateMask": "..." }
        // Only ruleset_name updates are honored; release rename is not supported.
        const releaseName = `projects/${tenantProjectId}/releases/cloud.firestore`;
        let releaseResponse = await fetch(`https://firebaserules.googleapis.com/v1/${releaseName}`, {
            method: 'PATCH',
            headers: {
                Authorization: `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                release: {
                    name: releaseName,
                    rulesetName: rulesetName,
                },
                updateMask: 'ruleset_name',
            }),
        });
        if (!releaseResponse.ok && releaseResponse.status === 404) {
            // Release does not exist yet (first deployment) — create it instead.
            v2_1.logger.info('Release not found; creating it', { tenantProjectId });
            releaseResponse = await fetch(`https://firebaserules.googleapis.com/v1/projects/${tenantProjectId}/releases`, {
                method: 'POST',
                headers: {
                    Authorization: `Bearer ${accessToken}`,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    name: releaseName,
                    rulesetName: rulesetName,
                }),
            });
        }
        if (!releaseResponse.ok) {
            const errorText = await releaseResponse.text();
            v2_1.logger.error('Release deployment failed', { tenantProjectId, status: releaseResponse.status, error: errorText, rulesetName });
            throw new https_1.HttpsError('internal', `deployTenantRules release deployment failed for ${tenantProjectId}: HTTP ${releaseResponse.status}: ${errorText}`, { operation: 'release deployment', tenantProjectId, status: releaseResponse.status, response: errorText });
        }
        v2_1.logger.info('Released ruleset', { tenantProjectId, rulesetName });
        // ---- Step 3: Deploy Indexes ----
        const indexesUrl = `https://firestore.googleapis.com/v1/projects/${tenantProjectId}/databases/(default)/indexes`;
        let indexesCreated = 0;
        let indexesSkipped = 0;
        // The indexes file structure has an "indexes" array
        const indexes = indexesContent.indexes || [];
        for (const index of indexes) {
            try {
                const indexResponse = await fetch(`https://firestore.googleapis.com/v1/projects/${tenantProjectId}/databases/(default)/indexes`, {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${accessToken}`,
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(index),
                });
                if (!indexResponse.ok) {
                    const errorText = await indexResponse.text();
                    const isAlreadyExists = errorText.includes('ALREADY_EXISTS') ||
                        errorText.includes('already exists');
                    if (isAlreadyExists) {
                        // Index already exists - this is idempotent, not an error
                        v2_1.logger.debug('Index already exists, skipping', { tenantProjectId });
                    }
                    else {
                        v2_1.logger.warn('Index deploy warning', { tenantProjectId, error: errorText });
                    }
                }
                else {
                    // Success
                }
            }
            catch (e) {
                v2_1.logger.warn('Index deploy error (non-fatal)', { tenantProjectId, error: e.message });
            }
        }
        // We can't easily track exact counts due to async nature, but we can report attempt
        v2_1.logger.info('Indexes deployment attempted', { tenantProjectId, totalIndexes: indexes.length });
        const durationMs = Date.now() - startTime;
        v2_1.logger.info('deployTenantRules completed successfully', {
            tenantProjectId,
            durationMs,
            rulesetName
        });
        return {
            success: true,
            message: `Rules and indexes deployed to ${tenantProjectId}`,
            ruleset: rulesetName,
            durationMs,
        };
    }
    catch (error) {
        const durationMs = Date.now() - startTime;
        v2_1.logger.error('deployTenantRules failed', {
            tenantProjectId,
            durationMs,
            error: error.message,
            stack: error.stack,
        });
        // Re-throw HttpsError as-is, wrap others
        if (error instanceof https_1.HttpsError) {
            throw error;
        }
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        // Check for permission errors in the message
        if (errorMessage.includes('PERMISSION_DENIED') || errorMessage.includes('permission-denied')) {
            throw new https_1.HttpsError('permission-denied', `Service account lacks required IAM roles on tenant project ${tenantProjectId}. ` +
                `Ensure the master service account has "Firebase Rules Admin" and "Datastore Index Admin" roles. ` +
                `Original error: ${errorMessage}`, { actionRequired: true, tenantProjectId });
        }
        throw new https_1.HttpsError('internal', `Deployment failed: ${errorMessage}`);
    }
}
/**
 * HTTP entrypoint: CORS + manual Bearer-token auth + callable-style
 * request/response envelope.
 */
exports.deployTenantRules = (0, https_1.onRequest)({
    secrets: [firebaseAdmin_1.serviceAccountJson],
    region: 'us-central1',
    maxInstances: 10,
    memory: '512MiB',
    timeoutSeconds: 300,
}, async (req, res) => {
    (0, httpAuth_1.applyCors)(req, res);
    // Browser preflight — respond directly.
    if (req.method === 'OPTIONS') {
        res.status(204).send('');
        return;
    }
    try {
        if (req.method !== 'POST') {
            throw new httpAuth_1.HttpEndpointError(405, 'invalid-argument', 'Use POST.');
        }
        // Manual auth: verify Authorization: Bearer <idToken> against master
        // project Auth and enforce the super_admin custom claim.
        await (0, httpAuth_1.requireSuperAdmin)(req);
        const data = (0, httpAuth_1.extractData)(req.body);
        const result = await handleDeployTenantRules(data);
        (0, httpAuth_1.sendResult)(res, result);
    }
    catch (e) {
        v2_1.logger.error('deployTenantRules request failed', {
            error: e.message,
            stack: e.stack,
        });
        (0, httpAuth_1.sendError)(res, e);
    }
});
//# sourceMappingURL=deployTenantRules.js.map