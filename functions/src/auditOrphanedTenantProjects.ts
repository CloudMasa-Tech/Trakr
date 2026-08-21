/**
 * Callable, super-admin-only audit of tenant-folder projects that are not
 * referenced by any current workspace firebaseProjectId binding.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { serviceAccountJson, initializeMasterAdmin, getMasterAccessToken } from './lib/firebaseAdmin';

const TENANT_FOLDER_ID = '818058604638';
const FOLDER_RESOURCE = `folders/${TENANT_FOLDER_ID}`;

type GcpProject = {
  projectId?: string;
  name?: string;
  state?: string;
  parent?: { type?: string; id?: string };
};

async function listTenantProjects(accessToken: string): Promise<GcpProject[]> {
  const projects: GcpProject[] = [];
  let pageToken = '';
  do {
    const params = new URLSearchParams({
      pageSize: '1000',
      filter: `parent.type:folder parent.id:${TENANT_FOLDER_ID}`,
    });
    if (pageToken) params.set('pageToken', pageToken);
    const response = await fetch(
      `https://cloudresourcemanager.googleapis.com/v3/projects?${params.toString()}`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );
    if (!response.ok) {
      throw new Error(`Cloud Resource Manager project list failed: HTTP ${response.status} ${await response.text()}`);
    }
    const data = await response.json() as { projects?: GcpProject[]; nextPageToken?: string };
    projects.push(...(data.projects ?? []));
    pageToken = data.nextPageToken ?? '';
  } while (pageToken);
  return projects;
}

export const auditOrphanedTenantProjects = onCall(
  {
    secrets: [serviceAccountJson],
    region: 'us-central1',
    maxInstances: 2,
    memory: '256MiB',
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth?.token?.super_admin) {
      throw new HttpsError('permission-denied', 'Only superadmins can audit tenant projects.');
    }

    try {
      const masterApp = initializeMasterAdmin();
      const masterDb = masterApp.firestore();
      const workspaceSnapshot = await masterDb.collection('workspaces').get();
      const referenced = new Set<string>();
      const workspaceByProject = new Map<string, string[]>();
      for (const doc of workspaceSnapshot.docs) {
        const data = doc.data();
        const config = data.firebaseConfig as Record<string, unknown> | undefined;
        const projectId = typeof data.firebaseProjectId === 'string'
          ? data.firebaseProjectId.trim()
          : typeof config?.projectId === 'string' ? config.projectId.trim() : '';
        if (!projectId) continue;
        referenced.add(projectId);
        const owners = workspaceByProject.get(projectId) ?? [];
        owners.push(doc.id);
        workspaceByProject.set(projectId, owners);
      }

      const projects = await listTenantProjects(await getMasterAccessToken());
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
      logger.info('Tenant project orphan audit complete', {
        auditId: auditRef.id,
        orphanedCount: orphanedProjects.length,
        duplicateBindingCount: duplicateBindings.length,
      });
      return { success: true, auditId: auditRef.id, ...audit, scannedAt: new Date().toISOString() };
    } catch (error) {
      logger.error('Tenant project orphan audit failed', { error: error instanceof Error ? error.message : String(error) });
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', `Tenant project orphan audit failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  },
);
