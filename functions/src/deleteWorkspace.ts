/**
 * HTTP Cloud Function: deleteWorkspace (onRequest)
 *
 * Permanently deletes a tenant workspace and its associated GCP/Firebase project.
 * This is an irreversible operation that requires superadmin privileges.
 *
 * NOTE: Converted from onCall to onRequest because the Flutter Web client
 * invokes this endpoint via raw fetch/http.post with an EXPLICIT
 * `Authorization: Bearer <idToken>` header (the callable SDK was observed
 * sending empty Authorization headers). Auth is therefore verified manually
 * via admin.auth().verifyIdToken() + super_admin claim check.
 *
 * Request body: {"data": {"workspaceId","projectId","confirmation"}} (callable
 * envelope kept for compatibility; a flat body is also accepted).
 * Response body: {"result": {...}} on success, {"error": {...}} on failure.
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
 */

import { onRequest, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { serviceAccountJson, initializeMasterAdmin, getMasterAccessToken, getMasterAdmin } from './lib/firebaseAdmin';
import {
  applyCors,
  requireSuperAdmin,
  extractData,
  sendResult,
  sendError,
  HttpEndpointError,
} from './lib/httpAuth';

// Folder ID where tenant projects are created
const TENANT_FOLDER_ID = '818058604638';
const FOLDER_RESOURCE = `folders/${TENANT_FOLDER_ID}`;

async function handleDeleteWorkspace(
  data: Record<string, unknown>,
  callerEmail: string | undefined,
): Promise<{
  success: boolean;
  message: string;
  workspaceId: string;
  projectId: string;
  deletedAt: string;
}> {
  const startTime = Date.now();
  // Extract inputs
  const wsId = data.workspaceId as string;
  const projectId = data.projectId as string;
  const confirmation = data.confirmation as string;

  // ---- Input Validation ----
    if (!wsId || wsId.trim().length === 0) {
      throw new HttpsError('invalid-argument', 'workspaceId is required (string)');
    }
    if (!projectId || projectId.trim().length === 0) {
      throw new HttpsError('invalid-argument', 'projectId is required (string)');
    }
    if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId)) {
      throw new HttpsError(
        'invalid-argument',
        'projectId format invalid. Must be 6-30 chars, lowercase, start with letter, end with letter/digit, only hyphens allowed'
      );
    }
    if (confirmation !== 'DELETE') {
      throw new HttpsError(
        'invalid-argument',
        'Confirmation must be exactly "DELETE" to confirm irreversible deletion'
      );
    }

    // Prevent deleting master project
    const masterApp = initializeMasterAdmin();
    const masterProjectId = masterApp.options.projectId;
    if (projectId === masterProjectId) {
      throw new HttpsError(
        'invalid-argument',
        'Cannot delete the master/control-plane project'
      );
    }

    // Check if project was recently deleted (30-day block)
    try {
      const masterAppForCheck = getMasterAdmin();
      const masterDb = masterAppForCheck.firestore();
      const deletedDoc = await masterDb
          .collection('deleted_projects')
          .doc(projectId)
          .get();
      
      if (deletedDoc.exists) {
        const data = deletedDoc.data()!;
        const deletedAt = data.deletedAt?.toDate?.() || new Date(data.deletedAt);
        const daysSinceDeletion = (Date.now() - deletedAt.getTime()) / (1000 * 60 * 60 * 24);

        if (daysSinceDeletion < 30) {
          // The GCP project ID is in Google's 30-day soft-delete grace period.
          // This is NOT a reason to abort: the workspace record may still exist
          // in master Firestore (e.g. a previous deletion attempt failed partway,
          // or this is a retry). Per the lifecycle policy, we must proceed to
          // clean up the master Firestore records only — never mutate the GCP
          // project again. The CRM lifecycle-state check below is fail-closed
          // and will skip the GCP delete for projects already pending deletion.
          const daysRemaining = Math.ceil(30 - daysSinceDeletion);
          logger.info(
            'deleteWorkspace: project ID is in Google 30-day grace period — ' +
            'proceeding with Firestore-only cleanup',
            {
              projectId,
              workspaceId: wsId,
              daysSinceDeletion: Math.floor(daysSinceDeletion),
              daysRemaining,
            },
          );
        }
      }
} catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.warn('deleteWorkspace: failed to check deleted projects list', { error: e });
    }

    // ---- Step 1: Check project lifecycle state via CRM v3 GET ----
    // Before attempting parent verification or GCP deletion, check whether the
    // project is already being deleted (DELETE_REQUESTED / DELETE_IN_PROGRESS)
    // or does not exist at all (404). In those cases, skip the GCP delete call
    // entirely and proceed straight to Firestore cleanup.
    let alreadyBeingDeleted = false;
    try {
      const accessToken = await getMasterAccessToken();
      const crmCheckUrl = `https://cloudresourcemanager.googleapis.com/v3/projects/${projectId}?view=FULL`;
      const checkResponse = await fetch(crmCheckUrl, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
      });

      if (checkResponse.ok) {
        const checkData: any = await checkResponse.json();
        const lifecycleState: string | undefined = checkData.lifecycleState;

        if (lifecycleState === 'DELETE_REQUESTED' || lifecycleState === 'DELETE_IN_PROGRESS') {
          alreadyBeingDeleted = true;
          logger.info('deleteWorkspace: project is already being deleted — skipping GCP delete', {
            projectId,
            lifecycleState,
          });
        } else {
          // Project is ACTIVE — verify it lives under our managed folder.
          // CRM v3 API returns parent as a string (e.g. "folders/818058604638")
          const projectParent = (typeof checkData?.parent === 'string')
              ? checkData.parent
              : (checkData?.parent?.name || `projects/${projectId}`);
          const expectedParent = `folders/${TENANT_FOLDER_ID}`;
          if (projectParent !== expectedParent) {
            throw new HttpsError(
              'failed-precondition',
              `This project exists outside the managed tenant folder ` +
              `(${expectedParent}) and cannot be safely auto-deleted. ` +
              `Manual review required. Project parent: ${projectParent}`,
              { actionRequired: true, projectId },
            );
          }
          logger.info('deleteWorkspace: project parent verified', { projectId, projectParent });
        }
      } else {
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
          logger.info('deleteWorkspace: project not found or mid-deletion — skipping GCP delete', {
            projectId,
            status,
            errText,
          });
        } else {
          // Genuine API failure (500, 403, etc.) — abort for safety
          logger.error('deleteWorkspace: failed to verify project — aborting', { projectId, status, errText });
          throw new HttpsError(
            'internal',
            `Could not verify project status (CRM returned ${status}) — ` +
            `aborting deletion for safety. Retry when the API is reachable.`,
          );
        }
      }
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      // Fail-closed: if we cannot reach CRM at all (network error, timeout,
      // outage), refuse to delete. A false "proceed" could destroy a project.
      logger.error('deleteWorkspace: project status check failed — aborting', { projectId, error: e });
      throw new HttpsError(
        'internal',
        'Could not verify project status — aborting deletion for safety. ' +
        'Retry when the CRM API is reachable.',
      );
    }

    try {
      logger.info('deleteWorkspace: starting deletion', { workspaceId: wsId, projectId, alreadyBeingDeleted });

      if (!alreadyBeingDeleted) {
        // ---- Step 2: Delete GCP/Firebase Project via CRM v3 DELETE ----
        const accessToken = await getMasterAccessToken();
        const projectDeleteUrl = `https://cloudresourcemanager.googleapis.com/v3/projects/${projectId}`;

        logger.info('Deleting GCP project', { projectId });

        const deleteResponse = await fetch(projectDeleteUrl, {
          method: 'DELETE',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
        });

        if (!deleteResponse.ok) {
          const errorText = await deleteResponse.text();
          logger.error('Project deletion failed', { projectId, status: deleteResponse.status, error: errorText });

          if (deleteResponse.status === 403) {
            throw new HttpsError(
              'permission-denied',
              `Service account lacks "Project Deleter" role on folder ${TENANT_FOLDER_ID}. ` +
              `Grant it via: gcloud resource-manager folders add-iam-policy-binding ${TENANT_FOLDER_ID} ` +
              `--member="serviceAccount:<MASTER_SERVICE_ACCOUNT_EMAIL>" --role="roles/resourcemanager.projectDeleter"`,
              { actionRequired: true, projectId },
            );
          }
          if (deleteResponse.status === 404) {
            // Project disappeared between our GET and DELETE — treat as already deleted
            logger.warn('Project vanished between check and delete — treating as already deleted', { projectId });
          } else if (errorText.includes('already pending deletion') ||
                     errorText.includes('DELETE_REQUESTED') ||
                     errorText.includes('DELETE_IN_PROGRESS')) {
            logger.warn('Project already pending deletion', { projectId });
          } else {
            throw new HttpsError('internal', `Failed to delete project: ${errorText}`);
          }
        } else {
          const operation = await deleteResponse.json() as { name: string };
          const operationName = operation.name;
          logger.info('Project deletion operation started', { projectId, operationName });

          // ---- Step 3: Poll for Operation Completion ----
          const operationUrl = `https://cloudresourcemanager.googleapis.com/v3/${operationName}`;

          let operationDone = false;
          let operationResult: any = null;
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
              logger.error('Operation polling failed', { projectId, operationName, error: errorText });
            } else {
              operationResult = await opResponse.json();
              operationDone = operationResult.done === true;

              if (operationDone) {
                if (operationResult.error) {
                  const errorMsg = operationResult.error.message || 'Unknown error';
                  logger.error('Project deletion operation failed', { projectId, error: errorMsg });
                  throw new HttpsError('internal', `Project deletion failed: ${errorMsg}`);
                }
                logger.info('Project deletion operation completed successfully', { projectId });
              } else {
                logger.debug('Project deletion still in progress', { projectId, attempt: pollAttempts });
              }
            }
          }

          if (!operationDone) {
            throw new HttpsError('deadline-exceeded', 'Project deletion timed out after 10 minutes');
          }
        }

        logger.info('GCP project deleted successfully', { projectId });
      } else {
        logger.info('deleteWorkspace: skipping GCP delete — project already pending deletion', { projectId });
      }

      // ---- Step 3: Clean up Master Firestore Records ----
      // Initialize master admin for Firestore operations
      const masterAppForCleanup = getMasterAdmin();
      const masterDb = masterAppForCleanup.firestore();
      
      // Delete workspace registry entry
      try {
        await masterDb.collection('workspaces').doc(wsId).delete();
        logger.info('Deleted workspace registry entry', { workspaceId: wsId });
      } catch (e) {
        logger.error('Failed to delete workspace registry entry', { workspaceId: wsId, error: e });
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
        logger.info('Deleted tenant_users index entries', { workspaceId: wsId });
      } catch (e) {
        logger.error('Failed to delete tenant_users entries', { workspaceId: wsId, error: e });
      }

      // Delete project allocation
      try {
        await _allocationsDelete(wsId, projectId);
      } catch (e) {
        logger.error('Failed to delete project allocation', { workspaceId: wsId, projectId, error: e });
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
        logger.info('Deleted provision logs', { workspaceId: wsId });
      } catch (e) {
        logger.error('Failed to delete provision logs', { workspaceId: wsId, error: e });
      }

      // ---- Step 4: Record Deletion Audit with 30-day block ----
      const deletedAt = new Date().toISOString();
      
      try {
        await masterDb.collection('deleted_projects').doc(projectId).set({
          projectId,
          workspaceId: wsId,
          deletedAt: admin.firestore.FieldValue.serverTimestamp(),
          deletedBy: callerEmail || 'unknown',
          deletionType: 'superadmin_manual',
        });
        logger.info('Recorded deletion in deleted_projects collection', { projectId });
      } catch (e) {
        logger.error('Failed to record deletion audit', { projectId, error: e });
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
      } catch (e) {
        logger.warn('Audit log write failed', { projectId, error: e });
      }

      const durationMs = Date.now() - startTime;
      logger.info('deleteWorkspace completed successfully', { 
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

    } catch (error) {
      const durationMs = Date.now() - startTime;
      logger.error('deleteWorkspace failed', { 
        workspaceId: wsId, 
        projectId, 
        durationMs, 
        error: (error as Error).message,
        stack: (error as Error).stack,
      });
      
      if (error instanceof HttpsError) {
        throw error;
      }
      
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      
      // Check for permission errors
      if (errorMessage.includes('PERMISSION_DENIED') || errorMessage.includes('permission-denied')) {
        throw new HttpsError(
          'permission-denied',
          `Service account lacks required IAM roles on folder ${TENANT_FOLDER_ID}. ` +
          `Ensure the master service account has "Project Deleter" role. ` +
          `Original error: ${errorMessage}`,
          { actionRequired: true, projectId }
        );
      }
      
      throw new HttpsError('internal', `Deletion failed: ${errorMessage}`);
    }
}

/**
 * HTTP entrypoint: CORS + manual Bearer-token auth + callable-style
 * request/response envelope.
 */
export const deleteWorkspace = onRequest(
  {
    secrets: [serviceAccountJson],
    region: 'us-central1',
    maxInstances: 3,
    memory: '512MiB',
    timeoutSeconds: 300,
  },
  async (req, res) => {
    applyCors(req, res);

    // Browser preflight — respond directly.
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    try {
      if (req.method !== 'POST') {
        throw new HttpEndpointError(405, 'invalid-argument', 'Use POST.');
      }

      // Manual auth: verify Authorization: Bearer <idToken> against master
      // project Auth and enforce the super_admin custom claim.
      const decoded = await requireSuperAdmin(req);

      const data = extractData(req.body);
      const result = await handleDeleteWorkspace(data, decoded.email);
      sendResult(res, result);
    } catch (e) {
      logger.error('deleteWorkspace request failed', {
        error: (e as Error).message,
        stack: (e as Error).stack,
      });
      sendError(res, e);
    }
  },
);

// Helper function to delete project allocation
async function _allocationsDelete(workspaceId: string, projectId: string): Promise<void> {
  const masterApp = getMasterAdmin();
  const masterDb = masterApp.firestore();
  
  try {
    await Promise.all([
      masterDb.collection('project_allocations').doc(projectId).delete().catch(() => undefined),
      masterDb.collection('firebase_project_allocations').doc(projectId).delete().catch(() => undefined),
    ]);
  } catch (e) {
    // Ignore if not found
  }
}