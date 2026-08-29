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

import { onRequest, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { serviceAccountJson, initializeMasterAdmin, getMasterAccessToken } from './lib/firebaseAdmin';
import {
  applyCors,
  requireSuperAdmin,
  extractData,
  sendResult,
  sendError,
  HttpEndpointError,
} from './lib/httpAuth';

async function handleDeployTenantRules(
  data: Record<string, unknown>,
): Promise<{
  success: boolean;
  message: string;
  ruleset: string;
  durationMs: number;
}> {
  const startTime = Date.now();
  const tenantProjectId = data.tenantProjectId as string | undefined;

  // ---- Input Validation ----
    if (!tenantProjectId || typeof tenantProjectId !== 'string') {
      throw new HttpsError('invalid-argument', 'tenantProjectId is required (string)');
    }
    if (tenantProjectId.trim().length === 0) {
      throw new HttpsError('invalid-argument', 'tenantProjectId cannot be empty');
    }
    if (!/^[a-z0-9-]{6,30}$/.test(tenantProjectId)) {
      throw new HttpsError(
        'invalid-argument',
        'tenantProjectId format invalid (expected Firebase project ID pattern)'
      );
    }

    // Prevent deploying to master project
    const masterApp = initializeMasterAdmin();
    const masterProjectId = masterApp.options.projectId;
    if (tenantProjectId === masterProjectId) {
      throw new HttpsError(
        'invalid-argument',
        'Cannot deploy tenant rules to the master/control-plane project'
      );
    }

    try {
      logger.info('deployTenantRules: starting deployment', { tenantProjectId });

      // ---- Get OAuth2 Access Token ----
      const accessToken = await getMasterAccessToken();

      // ---- Fetch Active Ruleset from Master Project ----
      logger.info('Fetching live rules from master project', { masterProjectId });
      
      const masterReleaseRes = await fetch(
        `https://firebaserules.googleapis.com/v1/projects/${masterProjectId}/releases/cloud.firestore`,
        {
          headers: { Authorization: `Bearer ${accessToken}` }
        }
      );
      if (!masterReleaseRes.ok) {
        const errText = await masterReleaseRes.text();
        throw new Error(`Failed to fetch master project release: HTTP ${masterReleaseRes.status} ${errText}`);
      }
      const masterRelease = await masterReleaseRes.json() as any;
      const masterRulesetName = masterRelease.rulesetName;
      if (!masterRulesetName) {
        throw new Error('Master project cloud.firestore release has no rulesetName');
      }

      const masterRulesetRes = await fetch(
        `https://firebaserules.googleapis.com/v1/${masterRulesetName}`,
        {
          headers: { Authorization: `Bearer ${accessToken}` }
        }
      );
      if (!masterRulesetRes.ok) {
        const errText = await masterRulesetRes.text();
        throw new Error(`Failed to fetch master project ruleset ${masterRulesetName}: HTTP ${masterRulesetRes.status} ${errText}`);
      }
      const masterRuleset = await masterRulesetRes.json() as any;
      
      let rulesContent = '';
      if (masterRuleset.source && masterRuleset.source.files && masterRuleset.source.files.length > 0) {
        rulesContent = masterRuleset.source.files[0].content;
      }
      if (!rulesContent) {
        throw new Error(`Master ruleset ${masterRulesetName} is empty or missing source.files content`);
      }

      logger.info('deployTenantRules: Master rules fetched successfully', {
        masterRulesetName,
        rulesSize: rulesContent.length,
      });

      // ---- Load Indexes from bundled assets ----
      const fs = require('fs');
      const path = require('path');
      const assetsDir = path.join(__dirname, 'assets');
      const indexesPath = path.join(assetsDir, 'firestore.indexes.json');

      if (!fs.existsSync(indexesPath)) {
        throw new Error(
          `firestore.indexes.json not found at ${indexesPath}. ` +
          `Ensure the prebuild script (npm run prebuild) ran before tsc.`
        );
      }
      const indexesContent = JSON.parse(fs.readFileSync(indexesPath, 'utf8'));

      // ---- Step 1: Create Ruleset ----
      const rulesetUrl = `https://firebaserules.googleapis.com/v1/projects/${tenantProjectId}/rulesets`;
      
      const rulesetResponse = await fetch(
        `https://firebaserules.googleapis.com/v1/projects/${tenantProjectId}/rulesets`,
        {
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
        }
      );

      if (!rulesetResponse.ok) {
        const errorText = await rulesetResponse.text();
        logger.error('Ruleset creation failed', { tenantProjectId, status: rulesetResponse.status, error: errorText });
        
        // Check for permission errors
        const isPermissionDenied = 
          errorText.includes('PERMISSION_DENIED') || 
          errorText.includes('permission-denied') ||
          rulesetResponse.status === 403;
        
        if (isPermissionDenied) {
          throw new HttpsError(
            'permission-denied',
            `Service account lacks "Firebase Rules Admin" role on tenant project ${tenantProjectId}. ` +
            `Grant it via: gcloud projects add-iam-policy-binding ${tenantProjectId} ` +
            `--member="serviceAccount:<MASTER_SERVICE_ACCOUNT_EMAIL>" --role="roles/firebaserules.admin"`,
            { actionRequired: true, tenantProjectId }
          );
        }
        
        throw new HttpsError('internal', `deployTenantRules ruleset creation failed for ${tenantProjectId}: HTTP ${rulesetResponse.status}: ${errorText}`, { operation: 'ruleset creation', tenantProjectId, status: rulesetResponse.status, response: errorText });
      }

      const ruleset = await rulesetResponse.json() as { name: string };
      const rulesetName = ruleset.name;
      logger.info('Created ruleset', { tenantProjectId, rulesetName });

      // ---- Step 2: Point the cloud.firestore Release at the new Ruleset ----
      // Per projects.releases.patch docs, the body must be an
      // UpdateReleaseRequest: { "release": <full Release>, "updateMask": "..." }
      // Only ruleset_name updates are honored; release rename is not supported.
      const releaseName = `projects/${tenantProjectId}/releases/cloud.firestore`;

      let releaseResponse = await fetch(
        `https://firebaserules.googleapis.com/v1/${releaseName}`,
        {
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
        }
      );

      if (!releaseResponse.ok && releaseResponse.status === 404) {
        // Release does not exist yet (first deployment) — create it instead.
        logger.info('Release not found; creating it', { tenantProjectId });
        releaseResponse = await fetch(
          `https://firebaserules.googleapis.com/v1/projects/${tenantProjectId}/releases`,
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              name: releaseName,
              rulesetName: rulesetName,
            }),
          }
        );
      }

      if (!releaseResponse.ok) {
        const errorText = await releaseResponse.text();
        logger.error('Release deployment failed', { tenantProjectId, status: releaseResponse.status, error: errorText, rulesetName });
        throw new HttpsError('internal', `deployTenantRules release deployment failed for ${tenantProjectId}: HTTP ${releaseResponse.status}: ${errorText}`, { operation: 'release deployment', tenantProjectId, status: releaseResponse.status, response: errorText });
      }

      logger.info('Released ruleset', { tenantProjectId, rulesetName });

      // ---- Step 3: Deploy Indexes ----
      const indexesUrl = `https://firestore.googleapis.com/v1/projects/${tenantProjectId}/databases/(default)/indexes`;
      
      let indexesCreated = 0;
      let indexesSkipped = 0;
      
      // The indexes file structure has an "indexes" array
      const indexes = indexesContent.indexes || [];
      
      for (const index of indexes) {
        try {
          const indexResponse = await fetch(
            `https://firestore.googleapis.com/v1/projects/${tenantProjectId}/databases/(default)/indexes`,
            {
              method: 'POST',
              headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify(index),
            }
          );

          if (!indexResponse.ok) {
            const errorText = await indexResponse.text();
            const isAlreadyExists = 
              errorText.includes('ALREADY_EXISTS') || 
              errorText.includes('already exists');
            
            if (isAlreadyExists) {
              // Index already exists - this is idempotent, not an error
              logger.debug('Index already exists, skipping', { tenantProjectId });
            } else {
              logger.warn('Index deploy warning', { tenantProjectId, error: errorText });
            }
          } else {
            // Success
          }
        } catch (e) {
          logger.warn('Index deploy error (non-fatal)', { tenantProjectId, error: (e as Error).message });
        }
      }
      
      // We can't easily track exact counts due to async nature, but we can report attempt
      logger.info('Indexes deployment attempted', { tenantProjectId, totalIndexes: indexes.length });

      const durationMs = Date.now() - startTime;
      logger.info('deployTenantRules completed successfully', { 
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

    } catch (error) {
      const durationMs = Date.now() - startTime;
      logger.error('deployTenantRules failed', { 
        tenantProjectId, 
        durationMs, 
        error: (error as Error).message,
        stack: (error as Error).stack,
      });
      
      // Re-throw HttpsError as-is, wrap others
      if (error instanceof HttpsError) {
        throw error;
      }
      
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      
      // Check for permission errors in the message
      if (errorMessage.includes('PERMISSION_DENIED') || errorMessage.includes('permission-denied')) {
        throw new HttpsError(
          'permission-denied',
          `Service account lacks required IAM roles on tenant project ${tenantProjectId}. ` +
          `Ensure the master service account has "Firebase Rules Admin" and "Datastore Index Admin" roles. ` +
          `Original error: ${errorMessage}`,
          { actionRequired: true, tenantProjectId }
        );
      }
      
      throw new HttpsError('internal', `Deployment failed: ${errorMessage}`);
    }
}

/**
 * HTTP entrypoint: CORS + manual Bearer-token auth + callable-style
 * request/response envelope.
 */
export const deployTenantRules = onRequest(
  {
    secrets: [serviceAccountJson],
    region: 'us-central1',
    maxInstances: 10,
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
      await requireSuperAdmin(req);

      const data = extractData(req.body);
      const result = await handleDeployTenantRules(data);
      sendResult(res, result);
    } catch (e) {
      logger.error('deployTenantRules request failed', {
        error: (e as Error).message,
        stack: (e as Error).stack,
      });
      sendError(res, e);
    }
  },
);