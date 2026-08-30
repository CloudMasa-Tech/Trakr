"use strict";
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
exports.registerTenantMember = void 0;
/**
 * HTTP Cloud Function: registerTenantMember (onRequest)
 *
 * Writes/refreshes a member's entry in the Master control-plane login index
 * (`tenant_users/{email}`) so the person can sign in with only their email
 * (no workspace code). The tenant Flutter client creates the Auth + Firestore
 * records itself; this function records the login-identity on the Master.
 *
 * Why it lives on the MASTER project:
 *   Tenant projects are Spark — no Cloud Functions. The index lives on Master
 *   and Master Firestore rules only allow `isSuperAdmin()` to write it, so a
 *   tenant client can never write it directly. The function uses the Master
 *   Admin SDK (SERVICE_ACCOUNT_JSON), which bypasses rules, after verifying
 *   the caller is a genuine authenticated member of the target tenant.
 *
 * Authorization (two paths):
 *   PATH A — Platform operator: caller holds a super_admin claim on the MASTER
 *            project (same check as deleteTenantUser / deployTenantRules).
 *   PATH B — Authenticated tenant member: caller's ID token is minted by the
 *            TENANT project (verified with the master SA scoped to it). The
 *            tenant's own security rules already gate who may create accounts,
 *            so this avoids an adminEmail-only gate that would break manager
 *            on-boarding. Registering an optimistic login hint is additive and
 *            cannot grant access: the tenant project still rejects logins for
 *            emails that have no real account there.
 *
 * Request (callable envelope {"data": {...}} or flat body):
 *   { "projectId": "<tenant firebase project id>",
 *     "email":     "<member email>",
 *     "role":      "<login role; e.g. user|admin>",   // optional, default "user"
 *     "name":      "<display name>" }                 // optional
 *
 * Response: {"result": {"success", "email", "workspaceId", "role",
 *                       "platformOperator", "created"}}
 *
 * Requirements:
 *   - SERVICE_ACCOUNT_JSON secret (master SA) must be configured.
 *   - The tenant project must already have a `workspaces` registry entry for
 *     this projectId (provisioned via createTenantProject).
 */
const https_1 = require("firebase-functions/v2/https");
const v2_1 = require("firebase-functions/v2");
const admin = __importStar(require("firebase-admin"));
const firebaseAdmin_1 = require("./lib/firebaseAdmin");
const httpAuth_1 = require("./lib/httpAuth");
const PROJECT_ID_RE = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
function extractBearer(req) {
    const raw = req.headers.authorization;
    const header = Array.isArray(raw) ? raw[0] : raw;
    const match = /^Bearer\s+(.+)$/i.exec(header ?? '');
    if (!match) {
        throw new httpAuth_1.HttpEndpointError(401, 'unauthenticated', 'Missing Authorization: Bearer <Firebase ID token> header.');
    }
    return match[1];
}
async function handleRegisterTenantMember(req, data) {
    // ── Input validation ────────────────────────────────────────────────
    const projectId = data.projectId ?? '';
    const email = (data.email ?? '').trim().toLowerCase();
    const role = (data.role ?? 'user').trim().toLowerCase() || 'user';
    const name = (data.name ?? '').trim();
    if (!PROJECT_ID_RE.test(projectId)) {
        throw new httpAuth_1.HttpEndpointError(400, 'invalid-argument', 'projectId is required and must be a valid Firebase project ID.');
    }
    if (!EMAIL_RE.test(email)) {
        throw new httpAuth_1.HttpEndpointError(400, 'invalid-argument', 'A valid email is required.');
    }
    const masterProjectId = (0, firebaseAdmin_1.initializeMasterAdmin)().options.projectId;
    if (projectId === masterProjectId) {
        throw new httpAuth_1.HttpEndpointError(400, 'invalid-argument', 'Cannot register members of the master/control-plane project with this function.');
    }
    // ── Load workspace registry record for the tenant project ───────────
    const masterDb = (0, firebaseAdmin_1.getMasterAdmin)().firestore();
    const wsSnap = await masterDb
        .collection('workspaces')
        .where('firebaseProjectId', '==', projectId)
        .limit(1)
        .get();
    const wsDoc = wsSnap.docs[0];
    const workspaceId = wsDoc?.id ?? '';
    if (!workspaceId) {
        throw new httpAuth_1.HttpEndpointError(404, 'not-found', `No workspace registry entry for project "${projectId}". Provision the tenant before onboarding members.`);
    }
    // ── Authorization ───────────────────────────────────────────────────
    const bearer = extractBearer(req);
    // PATH A — platform super admin (token verified against the MASTER project).
    let platformOperator = false;
    try {
        const decodedMaster = await (0, firebaseAdmin_1.getMasterAdmin)().auth().verifyIdToken(bearer);
        if (decodedMaster.super_admin === true) {
            platformOperator = true;
        }
    }
    catch {
        // Not a master superadmin token — fall through to PATH B.
    }
    if (!platformOperator) {
        // PATH B — authenticated member of the TENANT project.
        try {
            await (0, firebaseAdmin_1.getTenantAdminApp)(projectId).auth().verifyIdToken(bearer);
        }
        catch (e) {
            throw new httpAuth_1.HttpEndpointError(401, 'unauthenticated', `Invalid or expired ID token for tenant "${projectId}": ${e.message}`);
        }
    }
    // ── Upsert the Master login index entry (idempotent) ────────────────
    const now = admin.firestore.FieldValue.serverTimestamp();
    const ref = masterDb.collection('tenant_users').doc(email);
    const existing = await ref.get();
    const payload = {
        email,
        workspaceId,
        role,
        name,
        updatedAt: now,
    };
    if (!existing.exists) {
        payload.createdAt = now;
    }
    await ref.set(payload, { merge: true });
    v2_1.logger.info('registerTenantMember: index upserted', {
        email,
        workspaceId,
        projectId,
        platformOperator,
        created: !existing.exists,
    });
    return {
        success: true,
        email,
        workspaceId,
        role,
        platformOperator,
        created: !existing.exists,
    };
}
exports.registerTenantMember = (0, https_1.onRequest)({
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
        const result = await handleRegisterTenantMember(req, data);
        (0, httpAuth_1.sendResult)(res, result);
    }
    catch (error) {
        (0, httpAuth_1.sendError)(res, error);
    }
});
//# sourceMappingURL=registerTenantMember.js.map