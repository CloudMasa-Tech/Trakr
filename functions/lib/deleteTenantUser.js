"use strict";
/**
 * HTTP Cloud Function: deleteTenantUser (onRequest)
 *
 * Permanently deletes a single Firebase Auth user record from a TENANT project.
 * This is the server-side half of the "Delete Employee/Manager" action in the
 * tenant app: the Flutter client removes the Firestore directory + role docs
 * itself, then asks this function to remove the Auth account so the person can
 * no longer sign in to that tenant at all.
 *
 * Why it lives on the MASTER project:
 *   Tenant projects run on the Firebase Spark plan, so they have NO Cloud
 *   Functions and the client SDK can only delete the *currently signed-in*
 *   user. Auth-user deletion requires the Firebase Admin SDK, which is only
 *   available server-side. The master project (Blaze) is the natural control
 *   plane because it already holds the SERVICE_ACCOUNT_JSON secret and the
 *   workspace registry that maps tenant admins to their projects.
 *
 * Authorization (two accepted paths):
 *   PATH A — Platform operator: caller holds a super_admin claim on the MASTER
 *            project (same check as deleteWorkspace/deployTenantRules).
 *   PATH B — Tenant Company Admin: caller's ID token is minted by the TENANT
 *            project (verified via the master service account scoped to that
 *            project), and the token's email matches the `adminEmail` recorded
 *            in the master `workspaces` registry for that `projectId`.
 *
 * Request body (callable envelope {"data": {...}} or flat body):
 *   { "projectId": "<tenant firebase project id>",
 *     "uid":   "<target auth uid>",        // optional, preferred
 *     "email": "<target auth email>" }     // used when uid is absent
 *
 * Response: {"result": {"success": true, "projectId", "uid", "email", "deletedAt"}}
 *
 * Requirements / IAM:
 *   - SERVICE_ACCOUNT_JSON secret (master SA) must be configured.
 *   - The master SA MUST be granted `roles/firebaseauth.admin` on every tenant
 *     project before DELETE is allowed (one-time folder-level IAM grant under
 *     folders/818058604638). Without it the call fails with a clear message.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteTenantUser = void 0;
const https_1 = require("firebase-functions/v2/https");
const v2_1 = require("firebase-functions/v2");
const firebaseAdmin_1 = require("./lib/firebaseAdmin");
const httpAuth_1 = require("./lib/httpAuth");
const PROJECT_ID_RE = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
function extractBearer(req) {
    const raw = req.headers.authorization;
    const header = Array.isArray(raw) ? raw[0] : raw;
    const match = /^Bearer\s+(.+)$/i.exec(header ?? '');
    if (!match) {
        throw new httpAuth_1.HttpEndpointError(401, 'unauthenticated', 'Missing Authorization: Bearer <Firebase ID token> header.');
    }
    return match[1];
}
async function handleDeleteTenantUser(req, data) {
    // ── Input validation ────────────────────────────────────────────────
    const projectId = data.projectId ?? '';
    const targetUid = data.uid ?? '';
    const targetEmail = (data.email ?? '').trim().toLowerCase();
    if (!PROJECT_ID_RE.test(projectId)) {
        throw new httpAuth_1.HttpEndpointError(400, 'invalid-argument', 'projectId is required and must be a valid Firebase project ID (6-30 chars, lowercase).');
    }
    const masterProjectId = (0, firebaseAdmin_1.initializeMasterAdmin)().options.projectId;
    if (projectId === masterProjectId) {
        throw new httpAuth_1.HttpEndpointError(400, 'invalid-argument', 'Cannot delete auth users from the master/control-plane project with this function.');
    }
    if (!targetUid.trim() && targetEmail.length === 0) {
        throw new httpAuth_1.HttpEndpointError(400, 'invalid-argument', 'Either uid or email of the target user is required.');
    }
    // ── Load workspace registry record for the tenant project ───────────
    const masterDb = (0, firebaseAdmin_1.getMasterAdmin)().firestore();
    const wsSnap = await masterDb
        .collection('workspaces')
        .where('firebaseProjectId', '==', projectId)
        .limit(1)
        .get();
    const wsDoc = wsSnap.docs[0];
    const wsData = wsDoc?.data() ?? {};
    const tenantAdminEmail = (wsData.adminEmail ?? '').trim().toLowerCase();
    const tenantAdminUid = (wsData.adminUid ?? '').trim();
    // ── Authorization ───────────────────────────────────────────────────
    const bearer = extractBearer(req);
    // PATH A — platform super admin (token verified against the MASTER project).
    let platformOperator = false;
    let callerTenantAdmin = false;
    try {
        const decodedMaster = await (0, firebaseAdmin_1.getMasterAdmin)().auth().verifyIdToken(bearer);
        if (decodedMaster.super_admin === true) {
            platformOperator = true;
        }
    }
    catch {
        // Not a master token (or not a super admin) — fall through to PATH B.
    }
    if (!platformOperator) {
        // PATH B — tenant Company Admin. Verify the caller token against the
        // TENANT project, then require the caller to BE the recorded admin.
        const tenantApp = (0, firebaseAdmin_1.getTenantAdminApp)(projectId);
        let decodedTenant;
        try {
            decodedTenant = await tenantApp.auth().verifyIdToken(bearer);
        }
        catch (e) {
            throw new httpAuth_1.HttpEndpointError(401, 'unauthenticated', `Invalid or expired ID token for tenant "${projectId}": ${e.message}`);
        }
        const callerEmail = (decodedTenant.email ?? '').trim().toLowerCase();
        if (callerEmail.length === 0 || callerEmail !== tenantAdminEmail) {
            v2_1.logger.warn('deleteTenantUser: tenant-admin authorization failed', {
                projectId,
                callerEmail,
                recordedAdmin: tenantAdminEmail ? 'mismatch' : 'none',
            });
            throw new httpAuth_1.HttpEndpointError(403, 'permission-denied', 'Only the tenant Company Admin (or a platform super admin) can delete users.');
        }
        callerTenantAdmin = true;
    }
    // ── Resolve the target user ─────────────────────────────────────────
    const tenantApp = (0, firebaseAdmin_1.getTenantAdminApp)(projectId);
    const tenantAuth = tenantApp.auth();
    let targetRecord;
    try {
        if (targetUid.trim()) {
            targetRecord = await tenantAuth.getUser(targetUid.trim());
        }
        else {
            targetRecord = await tenantAuth.getUserByEmail(targetEmail);
        }
    }
    catch (error) {
        if (error?.code === 'auth/user-not-found') {
            // Already gone — the desired end state. Report success so the tenant
            // client treats removal as complete even if records were orphaned.
            return {
                success: true,
                projectId,
                uid: targetUid.trim(),
                email: targetEmail,
                platformOperator,
                deletedAt: new Date().toISOString(),
            };
        }
        throw error;
    }
    // A tenant Company Admin can never delete THEMSELVES (would strand the
    // company). Platform operators are exempt — full-workspace teardown is done
    // through deleteWorkspace.
    if (callerTenantAdmin) {
        const targetUidVal = targetRecord.uid;
        const targetEmailVal = (targetRecord.email ?? '').trim().toLowerCase();
        if (targetUidVal === tenantAdminUid || targetEmailVal === tenantAdminEmail) {
            throw new httpAuth_1.HttpEndpointError(412, 'failed-precondition', 'The tenant Company Admin cannot delete their own account from the team directory.');
        }
    }
    // ── Delete the auth record in the tenant project ────────────────────
    try {
        await tenantAuth.deleteUser(targetRecord.uid);
    }
    catch (error) {
        const msg = error instanceof Error ? error.message : 'unknown error';
        v2_1.logger.error('deleteTenantUser: deleteUser failed (check IAM roles/firebaseauth.admin)', {
            projectId,
            uid: targetRecord.uid,
            errorCode: error?.code,
            message: msg,
            actionRequired: 'roles/firebaseauth.admin on tenant project',
        });
        if (error?.code && String(error.code).toLowerCase().includes('permission')) {
            throw new https_1.HttpsError('permission-denied', `The master service account needs roles/firebaseauth.admin on "${projectId}". ${msg}`);
        }
        throw error;
    }
    v2_1.logger.info('deleteTenantUser: deleted', {
        projectId,
        uid: targetRecord.uid,
        email: targetRecord.email,
        platformOperator,
    });
    return {
        success: true,
        projectId,
        uid: targetRecord.uid,
        email: targetRecord.email ?? targetEmail,
        platformOperator,
        deletedAt: new Date().toISOString(),
    };
}
exports.deleteTenantUser = (0, https_1.onRequest)({
    secrets: [firebaseAdmin_1.serviceAccountJson],
    region: 'us-central1',
    maxInstances: 10,
    memory: '256MiB',
    timeoutSeconds: 60,
}, async (req, res) => {
    (0, httpAuth_1.applyCors)(req, res);
    if (req.method === 'OPTIONS') {
        res.status(204).end();
        return;
    }
    try {
        const data = (0, httpAuth_1.extractData)(req.body);
        const result = await handleDeleteTenantUser(req, data);
        (0, httpAuth_1.sendResult)(res, result);
    }
    catch (error) {
        (0, httpAuth_1.sendError)(res, error);
    }
});
//# sourceMappingURL=deleteTenantUser.js.map