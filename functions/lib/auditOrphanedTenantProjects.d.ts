export declare const auditOrphanedTenantProjects: import("firebase-functions/v2/https").CallableFunction<any, Promise<{
    scannedAt: string;
    folderId: string;
    folderResource: string;
    workspaceCount: number;
    tenantProjectCount: number;
    referencedProjectCount: number;
    orphanedProjects: {
        projectId: string | undefined;
        projectName: string;
        state: string;
        parent: {
            type?: string;
            id?: string;
        };
    }[];
    duplicateBindings: {
        projectId: string;
        workspaceIds: string[];
    }[];
    success: boolean;
    auditId: string;
}>, unknown>;
//# sourceMappingURL=auditOrphanedTenantProjects.d.ts.map