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
exports.auditOrphanedTenantProjects = void 0;
/**
 * Callable, super-admin-only audit of tenant-folder projects that are not
 * referenced by any current workspace firebaseProjectId binding.
 */
const https_1 = require("firebase-functions/v2/https");
const v2_1 = require("firebase-functions/v2");
const admin = __importStar(require("firebase-admin"));
const firebaseAdmin_1 = require("./lib/firebaseAdmin");
const TENANT_FOLDER_ID = '818058604638';
const FOLDER_RESOURCE = `folders/${TENANT_FOLDER_ID}`;
async function listTenantProjects(accessToken) {
    const projects = [];
    let pageToken = '';
    do {
        const params = new URLSearchParams({
            pageSize: '1000',
            filter: `parent.type:folder parent.id:${TENANT_FOLDER_ID}`,
        });
        if (pageToken)
            params.set('pageToken', pageToken);
        const response = await fetch(`https://cloudresourcemanager.googleapis.com/v3/projects?${params.toString()}`, { headers: { Authorization: `Bearer ${accessToken}` } });
        if (!response.ok) {
            throw new Error(`Cloud Resource Manager project list failed: HTTP ${response.status} ${await response.text()}`);
        }
        const data = await response.json();
        projects.push(...(data.projects ?? []));
        pageToken = data.nextPageToken ?? '';
    } while (pageToken);
    return projects;
}
exports.auditOrphanedTenantProjects = (0, https_1.onCall)({
    secrets: [firebaseAdmin_1.serviceAccountJson],
    region: 'us-central1',
    maxInstances: 2,
    memory: '256MiB',
    timeoutSeconds: 120,
}, async (request) => {
    if (!request.auth?.token?.super_admin) {
        throw new https_1.HttpsError('permission-denied', 'Only superadmins can audit tenant projects.');
    }
    try {
        const masterApp = (0, firebaseAdmin_1.initializeMasterAdmin)();
        const masterDb = masterApp.firestore();
        const workspaceSnapshot = await masterDb.collection('workspaces').get();
        const referenced = new Set();
        const workspaceByProject = new Map();
        for (const doc of workspaceSnapshot.docs) {
            const data = doc.data();
            const config = data.firebaseConfig;
            const projectId = typeof data.firebaseProjectId === 'string'
                ? data.firebaseProjectId.trim()
                : typeof config?.projectId === 'string' ? config.projectId.trim() : '';
            if (!projectId)
                continue;
            referenced.add(projectId);
            const owners = workspaceByProject.get(projectId) ?? [];
            owners.push(doc.id);
            workspaceByProject.set(projectId, owners);
        }
        const projects = await listTenantProjects(await (0, firebaseAdmin_1.getMasterAccessToken)());
        const orphanedProjects = projects
            .filter((project) => project.projectId && !referenced.has(project.projectId))
            .map((project) => ({
            projectId: project.projectId,
            projectName: project.name ?? '',
            state: project.state ?? '',
            parent: project.parent ?? { type: 'folder', id: TENANT_FOLDER_ID },
        }));
        const duplicateBindings = [...workspaceByProject.entries()]
            .filter(([, owners]) => owners.length > 1)
            .map(([projectId, workspaceIds]) => ({ projectId, workspaceIds }));
        const audit = {
            folderId: TENANT_FOLDER_ID,
            folderResource: FOLDER_RESOURCE,
            workspaceCount: workspaceSnapshot.size,
            tenantProjectCount: projects.length,
            referencedProjectCount: referenced.size,
            orphanedProjects,
            duplicateBindings,
            scannedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        const auditRef = await masterDb.collection('orphaned_project_audits').add(audit);
        v2_1.logger.info('Tenant project orphan audit complete', {
            auditId: auditRef.id,
            orphanedCount: orphanedProjects.length,
            duplicateBindingCount: duplicateBindings.length,
        });
        return { success: true, auditId: auditRef.id, ...audit, scannedAt: new Date().toISOString() };
    }
    catch (error) {
        v2_1.logger.error('Tenant project orphan audit failed', { error: error instanceof Error ? error.message : String(error) });
        if (error instanceof https_1.HttpsError)
            throw error;
        throw new https_1.HttpsError('internal', `Tenant project orphan audit failed: ${error instanceof Error ? error.message : String(error)}`);
    }
});
//# sourceMappingURL=auditOrphanedTenantProjects.js.map