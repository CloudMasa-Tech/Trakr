/**
 * TRAKR Cloud Functions - Main Entry Point
 *
 * Exports all callable Cloud Functions for the TRAKR platform.
 * Functions are deployed as Gen 2 callable functions with Secret Manager integration.
 *
 * Deploy: firebase deploy --only functions --project trakradminsetup-28437
 * Test: firebase functions:shell (then call deployTenantRules({tenantProjectId: 'test-123'}))
 */
export { deployTenantRules } from './deployTenantRules';
export { setSuperAdminClaim } from './setSuperAdminClaim';
export { createTenantProject } from './createTenantProject';
export { deleteWorkspace } from './deleteWorkspace';
export { deleteTenantUser } from './deleteTenantUser';
export { registerTenantMember } from './registerTenantMember';
export { auditOrphanedTenantProjects } from './auditOrphanedTenantProjects';
//# sourceMappingURL=index.d.ts.map