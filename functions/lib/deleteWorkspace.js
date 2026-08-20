"use strict";
/**
 * Callable Cloud Function: deleteWorkspace
 *
 * Permanently deletes a tenant workspace and its associated GCP/Firebase project.
 * This is an irreversible operation that requires superadmin privileges.
 *
 * Flow:
 * 1. Validates superadmin authorization
 * 2. Validates input (workspaceId, projectId)
 * 3. Deletes the GCP/Firebase project using Cloud Resource Manager API
 * 4. After successful project deletion, cleans up master Firestore records
 * 5. Records audit log with deletion details and 30-day reuse block
 *
 * Requirements:
 * - Caller must be authenticated superadmin (custom claim super_admin == true)
 * - Master service account needs roles/resourcemanager.projectDeleter on the folder
 * - SERVICE_ACCOUNT_JSON secret must be configured
 *
 * @param data.workspaceId - The workspace ID to delete
 * @param data.projectId - The Firebase project ID to delete (must match workspace)
 * @param data.confirmation - Must be "DELETE" to confirm irreversible action
 * @returns { success, message, projectId, workspaceId, deletedAt }
 * @throws HttpsError if not superadmin, invalid input, or deletion fails
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
exports.deleteWorkspace = void 0;
const https_1 = require("firebase-functions/v2/https");
const v2_1 = require("firebase-functions/v2");
const admin = __importStar(require("firebase-admin"));
const firebaseAdmin_1 = require("./lib/firebaseAdmin");
// Folder ID where tenant projects are created
const TENANT_FOLDER_ID = '818058604638';
const FOLDER_RESOURCE = `folders/${TENANT_FOLDER_ID}`;
exports.deleteWorkspace = (0, https_1.onCall)({
    secrets: [firebaseAdmin_1.serviceAccountJson],
    region: 'us-central1',
    maxInstances: 3,
    memory: '512MiB',
    timeoutSeconds: 300,
}, async (request) => {
    const startTime = Date.now();
    // Extract inputs
    const wsId = request.data?.workspaceId;
    const projectId = request.data?.projectId;
    const confirmation = request.data?.confirmation;
    // ---- Auth/Authorization ----
    if (!request.auth?.token?.super_admin) {
        v2_1.logger.warn('deleteWorkspace: permission denied - not superadmin', {
            uid: request.auth?.uid,
            email: request.auth?.token?.email,
            hasSuperAdminClaim: request.auth?.token?.super_admin,
        });
        throw new https_1.HttpsError('permission-denied', 'Only superadmins can delete workspaces. Missing super_admin custom claim.');
    }
    // ---- Input Validation ----
    if (!wsId || wsId.trim().length === 0) {
        throw new https_1.HttpsError('invalid-argument', 'workspaceId is required (string)');
    }
    if (!projectId || projectId.trim().length === 0) {
        throw new https_1.HttpsError('invalid-argument', 'projectId is required (string)');
    }
    if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId)) {
        throw new https_1.HttpsError('invalid-argument', 'projectId format invalid. Must be 6-30 chars, lowercase, start with letter, end with letter/digit, only hyphens allowed');
    }
    if (confirmation !== 'DELETE') {
        throw new https_1.HttpsError('invalid-argument', 'Confirmation must be exactly "DELETE" to confirm irreversible deletion');
    }
    // Prevent deleting master project
    const masterApp = (0, firebaseAdmin_1.initializeMasterAdmin)();
    const masterProjectId = masterApp.options.projectId;
    if (projectId === masterProjectId) {
        throw new https_1.HttpsError('invalid-argument', 'Cannot delete the master/control-plane project');
    }
    // Check if project was recently deleted (30-day block)
    try {
        const masterAppForCheck = (0, firebaseAdmin_1.getMasterAdmin)();
        const masterDb = masterAppForCheck.firestore();
        const deletedDoc = await masterDb
            .collection('deleted_projects')
            .doc(projectId)
            .get();
        if (deletedDoc.exists) {
            const data = deletedDoc.data();
            const deletedAt = data.deletedAt?.toDate?.() || new Date(data.deletedAt);
            const daysSinceDeletion = (Date.now() - deletedAt.getTime()) / (1000 * 60 * 60 * 24);
            if (daysSinceDeletion < 30) {
                const daysRemaining = Math.ceil(30 - daysSinceDeletion);
                throw new https_1.HttpsError('failed-precondition', `This project ID was deleted ${Math.floor(daysSinceDeletion)} days ago and is in Google's 30-day grace period. ` +
                    `Please wait ${daysRemaining} more days before reusing this project ID, or use a different project ID.`);
            }
        }
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        v2_1.logger.warn('deleteWorkspace: failed to check deleted projects list', { error: e });
    }
    // ---- Step 1: Check project lifecycle state via CRM v3 GET ----
    // Before attempting parent verification or GCP deletion, check whether the
    // project is already being deleted (DELETE_REQUESTED / DELETE_IN_PROGRESS)
    // or does not exist at all (404). In those cases, skip the GCP delete call
    // entirely and proceed straight to Firestore cleanup.
    let alreadyBeingDeleted = false;
    try {
        const accessToken = await (0, firebaseAdmin_1.getMasterAccessToken)();
        const crmCheckUrl = `https://cloudresourcemanager.googleapis.com/v3/projects/${projectId}?view=FULL`;
        const checkResponse = await fetch(crmCheckUrl, {
            method: 'GET',
            headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
            },
        });
        if (checkResponse.ok) {
            const checkData = await checkResponse.json();
            const lifecycleState = checkData.lifecycleState;
            if (lifecycleState === 'DELETE_REQUESTED' || lifecycleState === 'DELETE_IN_PROGRESS') {
                alreadyBeingDeleted = true;
                v2_1.logger.info('deleteWorkspace: project is already being deleted — skipping GCP delete', {
                    projectId,
                    lifecycleState,
                });
            }
            else {
                // Project is ACTIVE — verify it lives under our managed folder.
                // CRM v3 API returns parent as a string (e.g. "folders/818058604638")
                const projectParent = (typeof checkData?.parent === 'string')
                    ? checkData.parent
                    : (checkData?.parent?.name || `projects/${projectId}`);
                const expectedParent = `folders/${TENANT_FOLDER_ID}`;
                if (projectParent !== expectedParent) {
                    throw new https_1.HttpsError('failed-precondition', `This project exists outside the managed tenant folder ` +
                        `(${expectedParent}) and cannot be safely auto-deleted. ` +
                        `Manual review required. Project parent: ${projectParent}`, { actionRequired: true, projectId });
                }
                v2_1.logger.info('deleteWorkspace: project parent verified', { projectId, projectParent });
            }
        }
        else {
            const errText = await checkResponse.text();
            const status = checkResponse.status;
            // 404 = project already gone (fully deleted or never existed in CRM view)
            // 400 = project in a transitional state (e.g., already pending deletion)
            // In both cases, skip GCP delete and proceed to Firestore cleanup.
            if (status === 404 || status === 400 ||
                errText.includes('DELETE_REQUESTED') ||
                errText.includes('DELETE_IN_PROGRESS') ||
                errText.includes('already pending deletion') ||
                errText.includes('not found')) {
                alreadyBeingDeleted = true;
                v2_1.logger.info('deleteWorkspace: project not found or mid-deletion — skipping GCP delete', {
                    projectId,
                    status,
                    errText,
                });
            }
            else {
                // Genuine API failure (500, 403, etc.) — abort for safety
                v2_1.logger.error('deleteWorkspace: failed to verify project — aborting', { projectId, status, errText });
                throw new https_1.HttpsError('internal', `Could not verify project status (CRM returned ${status}) — ` +
                    `aborting deletion for safety. Retry when the API is reachable.`);
            }
        }
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        // Fail-closed: if we cannot reach CRM at all (network error, timeout,
        // outage), refuse to delete. A false "proceed" could destroy a project.
        v2_1.logger.error('deleteWorkspace: project status check failed — aborting', { projectId, error: e });
        throw new https_1.HttpsError('internal', 'Could not verify project status — aborting deletion for safety. ' +
            'Retry when the CRM API is reachable.');
    }
    try {
        v2_1.logger.info('deleteWorkspace: starting deletion', { workspaceId: wsId, projectId, alreadyBeingDeleted });
        if (!alreadyBeingDeleted) {
            // ---- Step 2: Delete GCP/Firebase Project via CRM v3 DELETE ----
            const accessToken = await (0, firebaseAdmin_1.getMasterAccessToken)();
            const projectDeleteUrl = `https://cloudresourcemanager.googleapis.com/v3/projects/${projectId}`;
            v2_1.logger.info('Deleting GCP project', { projectId });
            const deleteResponse = await fetch(projectDeleteUrl, {
                method: 'DELETE',
                headers: {
                    'Authorization': `Bearer ${accessToken}`,
                    'Content-Type': 'application/json',
                },
            });
            if (!deleteResponse.ok) {
                const errorText = await deleteResponse.text();
                v2_1.logger.error('Project deletion failed', { projectId, status: deleteResponse.status, error: errorText });
                if (deleteResponse.status === 403) {
                    throw new https_1.HttpsError('permission-denied', `Service account lacks "Project Deleter" role on folder ${TENANT_FOLDER_ID}. ` +
                        `Grant it via: gcloud resource-manager folders add-iam-policy-binding ${TENANT_FOLDER_ID} ` +
                        `--member="serviceAccount:<MASTER_SERVICE_ACCOUNT_EMAIL>" --role="roles/resourcemanager.projectDeleter"`, { actionRequired: true, projectId });
                }
                if (deleteResponse.status === 404) {
                    // Project disappeared between our GET and DELETE — treat as already deleted
                    v2_1.logger.warn('Project vanished between check and delete — treating as already deleted', { projectId });
                }
                else if (errorText.includes('already pending deletion') ||
                    errorText.includes('DELETE_REQUESTED') ||
                    errorText.includes('DELETE_IN_PROGRESS')) {
                    v2_1.logger.warn('Project already pending deletion', { projectId });
                }
                else {
                    throw new https_1.HttpsError('internal', `Failed to delete project: ${errorText}`);
                }
            }
            else {
                const operation = await deleteResponse.json();
                const operationName = operation.name;
                v2_1.logger.info('Project deletion operation started', { projectId, operationName });
                // ---- Step 3: Poll for Operation Completion ----
                const operationUrl = `https://cloudresourcemanager.googleapis.com/v3/${operationName}`;
                let operationDone = false;
                let operationResult = null;
                let pollAttempts = 0;
                const maxPollAttempts = 120;
                while (!operationDone && pollAttempts < maxPollAttempts) {
                    await new Promise(resolve => setTimeout(resolve, 5000));
                    pollAttempts++;
                    const opResponse = await fetch(operationUrl, {
                        method: 'GET',
                        headers: {
                            'Authorization': `Bearer ${accessToken}`,
                            'Content-Type': 'application/json',
                        },
                    });
                    if (!opResponse.ok) {
                        const errorText = await opResponse.text();
                        v2_1.logger.error('Operation polling failed', { projectId, operationName, error: errorText });
                    }
                    else {
                        operationResult = await opResponse.json();
                        operationDone = operationResult.done === true;
                        if (operationDone) {
                            if (operationResult.error) {
                                const errorMsg = operationResult.error.message || 'Unknown error';
                                v2_1.logger.error('Project deletion operation failed', { projectId, error: errorMsg });
                                throw new https_1.HttpsError('internal', `Project deletion failed: ${errorMsg}`);
                            }
                            v2_1.logger.info('Project deletion operation completed successfully', { projectId });
                        }
                        else {
                            v2_1.logger.debug('Project deletion still in progress', { projectId, attempt: pollAttempts });
                        }
                    }
                }
                if (!operationDone) {
                    throw new https_1.HttpsError('deadline-exceeded', 'Project deletion timed out after 10 minutes');
                }
            }
            v2_1.logger.info('GCP project deleted successfully', { projectId });
        }
        else {
            v2_1.logger.info('deleteWorkspace: skipping GCP delete — project already pending deletion', { projectId });
        }
        // ---- Step 3: Clean up Master Firestore Records ----
        // Initialize master admin for Firestore operations
        const masterAppForCleanup = (0, firebaseAdmin_1.getMasterAdmin)();
        const masterDb = masterAppForCleanup.firestore();
        // Delete workspace registry entry
        try {
            await masterDb.collection('workspaces').doc(wsId).delete();
            v2_1.logger.info('Deleted workspace registry entry', { workspaceId: wsId });
        }
        catch (e) {
            v2_1.logger.error('Failed to delete workspace registry entry', { workspaceId: wsId, error: e });
        }
        // Delete tenant_users index entries
        try {
            const snap = await masterDb
                .collection('tenant_users')
                .where('workspaceId', '==', wsId)
                .get();
            const batch = masterDb.batch();
            for (const doc of snap.docs) {
                batch.delete(doc.ref);
            }
            if (!snap.empty) {
                await batch.commit();
            }
            v2_1.logger.info('Deleted tenant_users index entries', { workspaceId: wsId });
        }
        catch (e) {
            v2_1.logger.error('Failed to delete tenant_users entries', { workspaceId: wsId, error: e });
        }
        // Delete project allocation
        try {
            await _allocationsDelete(wsId, projectId);
        }
        catch (e) {
            v2_1.logger.error('Failed to delete project allocation', { workspaceId: wsId, projectId, error: e });
        }
        // Delete provisioning logs
        try {
            const snap = await masterDb
                .collection('workspace_provision_logs')
                .where('workspaceId', '==', wsId)
                .get();
            const batch = masterDb.batch();
            for (const doc of snap.docs) {
                batch.delete(doc.ref);
            }
            if (!snap.empty) {
                await batch.commit();
            }
            v2_1.logger.info('Deleted provision logs', { workspaceId: wsId });
        }
        catch (e) {
            v2_1.logger.error('Failed to delete provision logs', { workspaceId: wsId, error: e });
        }
        // ---- Step 4: Record Deletion Audit with 30-day block ----
        const deletedAt = new Date().toISOString();
        try {
            await masterDb.collection('deleted_projects').doc(projectId).set({
                projectId,
                workspaceId: wsId,
                deletedAt: admin.firestore.FieldValue.serverTimestamp(),
                deletedBy: request.auth?.token?.email || 'unknown',
                deletionType: 'superadmin_manual',
            });
            v2_1.logger.info('Recorded deletion in deleted_projects collection', { projectId });
        }
        catch (e) {
            v2_1.logger.error('Failed to record deletion audit', { projectId, error: e });
        }
        // Log audit event
        try {
            await masterDb.collection('audit_logs').add({
                category: 'workspace',
                action: 'delete_workspace',
                actorRole: 'super_admin',
                targetType: 'workspace',
                targetId: wsId,
                targetName: projectId,
                changes: {
                    workspaceId: wsId,
                    projectId,
                    deletedAt: new Date().toISOString(),
                },
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
        catch (e) {
            v2_1.logger.warn('Audit log write failed', { projectId, error: e });
        }
        const durationMs = Date.now() - startTime;
        v2_1.logger.info('deleteWorkspace completed successfully', {
            workspaceId: wsId,
            projectId,
            durationMs
        });
        return {
            success: true,
            message: alreadyBeingDeleted
                ? `Project was already pending deletion; cleaned up workspace records for ${wsId}.`
                : `Workspace ${wsId} and project ${projectId} deleted successfully. The project ID is blocked for 30 days.`,
            workspaceId: wsId,
            projectId,
            deletedAt: new Date().toISOString(),
        };
    }
    catch (error) {
        const durationMs = Date.now() - startTime;
        v2_1.logger.error('deleteWorkspace failed', {
            workspaceId: wsId,
            projectId,
            durationMs,
            error: error.message,
            stack: error.stack,
        });
        if (error instanceof https_1.HttpsError) {
            throw error;
        }
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        // Check for permission errors
        if (errorMessage.includes('PERMISSION_DENIED') || errorMessage.includes('permission-denied')) {
            throw new https_1.HttpsError('permission-denied', `Service account lacks required IAM roles on folder ${TENANT_FOLDER_ID}. ` +
                `Ensure the master service account has "Project Deleter" role. ` +
                `Original error: ${errorMessage}`, { actionRequired: true, projectId });
        }
        throw new https_1.HttpsError('internal', `Deletion failed: ${errorMessage}`);
    }
});
// Helper function to delete project allocation
async function _allocationsDelete(workspaceId, projectId) {
    const masterApp = (0, firebaseAdmin_1.getMasterAdmin)();
    const masterDb = masterApp.firestore();
    try {
        await masterDb.collection('project_allocations').doc(projectId).delete();
    }
    catch (e) {
        // Ignore if not found
    }
}
//# sourceMappingURL=deleteWorkspace.js.map