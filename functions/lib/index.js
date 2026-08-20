"use strict";
/**
 * TRAKR Cloud Functions - Main Entry Point
 *
 * Exports all callable Cloud Functions for the TRAKR platform.
 * Functions are deployed as Gen 2 callable functions with Secret Manager integration.
 *
 * Deploy: firebase deploy --only functions --project trakradminsetup-28437
 * Test: firebase functions:shell (then call deployTenantRules({tenantProjectId: 'test-123'}))
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteWorkspace = exports.createTenantProject = exports.setSuperAdminClaim = exports.deployTenantRules = void 0;
var deployTenantRules_1 = require("./deployTenantRules");
Object.defineProperty(exports, "deployTenantRules", { enumerable: true, get: function () { return deployTenantRules_1.deployTenantRules; } });
var setSuperAdminClaim_1 = require("./setSuperAdminClaim");
Object.defineProperty(exports, "setSuperAdminClaim", { enumerable: true, get: function () { return setSuperAdminClaim_1.setSuperAdminClaim; } });
var createTenantProject_1 = require("./createTenantProject");
Object.defineProperty(exports, "createTenantProject", { enumerable: true, get: function () { return createTenantProject_1.createTenantProject; } });
var deleteWorkspace_1 = require("./deleteWorkspace");
Object.defineProperty(exports, "deleteWorkspace", { enumerable: true, get: function () { return deleteWorkspace_1.deleteWorkspace; } });
//# sourceMappingURL=index.js.map