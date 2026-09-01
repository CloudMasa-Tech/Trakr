/**
 * Scheduled Cloud Function: sendFestivalWishes (onSchedule)
 *
 * Runs once daily (06:30 Asia/Kolkata) on the MASTER/control-plane project.
 * Loops over every ACTIVE, fully-provisioned tenant workspace and, for each
 * tenant that has opted in via `app_config/festival_settings`, checks its
 * configured festival list. If a festival falls on TODAY (or TODAY + the
 * tenant's configurable `advanceDays`), sends to EVERY employee of that tenant:
 *   1. an in-app notification doc in the tenant's `notifications` collection
 *   2. an FCM push (multicast) via the tenant's Firebase project
 *   3. an email via the Vercel `sendFestivalEmail` endpoint
 *
 * Why it lives on the MASTER project:
 *   Tenant projects run on Firebase Spark — no Cloud Functions. The master
 *   project (Blaze) holds the SERVICE_ACCOUNT_JSON secret and the `workspaces`
 *   registry that maps tenant workspaces to their Firebase projects. We reuse
 *   getTenantAdminApp(projectId) so every tenant read/write is scoped to the
 *   correct tenant project — never the master project's business data.
 *
 * IAM requirement:
 *   The master service account must hold "Firebase Cloud Messaging Admin"
 *   (`roles/cloudmessaging.admin`, folder-level inherited) on every tenant
 *   project so tenantApp.messaging() can send pushes.
 *
 * Configuration (per tenant, tenant project):
 *   app_config/festival_settings:
 *   {
 *     enabled: true,
 *     advanceDays: 3,
 *     festivals: [{ id, name, date: "YYYY-MM-DD", enabled: true }],
 *     message: { title, body, emailSubject, emailBody }  // {festival}/{companyName}/{employeeName} placeholders
 *   }
 *
 * Idempotency: deterministic notification doc IDs + a per-tenant `lastSent`
 * marker keyed by festival+date, plus maxInstances:1, so an overlapping or
 * manual re-run cannot double-send.
 */

import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import {
  serviceAccountJson,
  getMasterAdmin,
  getTenantAdminApp,
} from './lib/firebaseAdmin';

// Collection prefixes that may carry FCM tokens + employee identity (per tenant).
const TOKEN_COLLECTIONS = ['users', 'staff', 'managers', 'admins'] as const;

const FESTIVAL_EMAIL_URL =
  process.env.FESTIVAL_EMAIL_URL ?? 'https://trakr-six.vercel.app/api/sendFestivalEmail';

const MAX_MULTICAST_TOKENS = 500; // hard Admin SDK limit per sendEachForMulticast

const NotificationBrand = 'TЯAKR';

type FestivalEntry = {
  id?: string;
  name?: string;
  date?: string; // YYYY-MM-DD, local/IST
  enabled?: boolean;
};

type FestivalSettings = {
  enabled: boolean;
  advanceDays: number;
  festivals: FestivalEntry[];
  message?: {
    title?: string;
    body?: string;
    emailSubject?: string;
    emailBody?: string;
  };
};

type Employee = {
  // Identity used for the in-app `recipient` (matches employee_home_screen's
  // `where('recipient', whereIn: identities)` lookup).
  recipient: string;
  employeeName: string;
  email: string;
  fcmTokens: string[]; // deduped across fcmToken + fcmTokens[]
};

/** Returns today's date as an IST-local YYYY-MM-DD string (timezone-safe). */
function istToday(): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Kolkata',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
  // en-CA yields YYYY-MM-DD.
  return parts;
}

function addDaysIso(isoDate: string, days: number): string {
  const [y, m, d] = isoDate.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + days);
  return dt.toISOString().slice(0, 10);
}

function stringVal(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

/** Reads and validates the tenant's festival settings. */
async function loadFestivalSettings(
  tenantDb: admin.firestore.Firestore,
): Promise<FestivalSettings | null> {
  const doc = await tenantDb.collection('app_config').doc('festival_settings').get();
  if (!doc.exists) return null;
  const data = doc.data() ?? {};
  if (data.enabled !== true) return null;

  const rawFestivals = Array.isArray(data.festivals) ? data.festivals : [];
  const festivals = rawFestivals
    .map((f) => ({
      id: stringVal((f as Record<string, unknown>)?.id),
      name: stringVal((f as Record<string, unknown>)?.name),
      date: stringVal((f as Record<string, unknown>)?.date),
      enabled: (f as Record<string, unknown>)?.enabled !== false,
    }))
    .filter((f) => f.enabled && /^\d{4}-\d{2}-\d{2}$/.test(f.date) && f.name);

  return {
    enabled: true,
    advanceDays: typeof data.advanceDays === 'number' ? data.advanceDays : 0,
    festivals,
    message: (data.message as FestivalSettings['message']) ?? undefined,
  };
}

/**
 * Reads employee identity + FCM tokens from all four token-bearing collections
 * in a tenant. Querying once per collection and unioning in memory avoids a
 * per-tenant N+1 token lookup and stays within a single scheduled run.
 */
async function collectTenantEmployees(
  tenantDb: admin.firestore.Firestore,
): Promise<Employee[]> {
  const map = new Map<string, Employee>();

  for (const collection of TOKEN_COLLECTIONS) {
    let lastDoc:
      | admin.firestore.QueryDocumentSnapshot<admin.firestore.DocumentData>
      | undefined;
    let hasMore = true;

    while (hasMore) {
      let query: admin.firestore.Query<admin.firestore.DocumentData> =
        tenantDb.collection(collection).orderBy('__name__').limit(500);
      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }
      const snap = await query.get();

      for (const doc of snap.docs) {
        const data = doc.data();
        const email = stringVal(data.email).toLowerCase();
        const employeeId = stringVal(data.employeeId);
        const rawName = stringVal(data.name);
        const name = rawName || stringVal(data.employeeName);
        // Recipient identity: the client looks up notifications by
        // employeeId / doc id / email (see employee_home_screen.dart).
        const recipient = employeeId || doc.id || email;
        if (!recipient) continue;

        const tokens = new Set<string>();
        if (typeof data.fcmToken === 'string' && data.fcmToken) {
          tokens.add(data.fcmToken);
        }
        if (Array.isArray(data.fcmTokens)) {
          for (const t of data.fcmTokens) {
            if (typeof t === 'string' && t) tokens.add(t);
          }
        }

        const existing = map.get(
          recipient + '|' + (email || '') + '|' + (employeeId || ''),
        );
        if (existing) {
          for (const t of tokens) existing.fcmTokens.push(t);
        } else {
          map.set(
            recipient + '|' + (email || '') + '|' + (employeeId || ''),
            { recipient, employeeName: name, email, fcmTokens: [...tokens] },
          );
        }
      }

      if (snap.size < 500) {
        hasMore = false;
      } else {
        lastDoc = snap.docs[snap.docs.length - 1];
      }
    }
  }

  return [...map.values()];
}

function fillTemplates(
  template: string,
  vars: { festival?: string; companyName?: string; employeeName?: string },
): string {
  return template
    .replace(/\{festival\}/g, vars.festival ?? 'Festival')
    .replace(/\{companyName\}/g, vars.companyName ?? '')
    .replace(/\{employeeName\}/g, vars.employeeName ?? '');
}

async function sendPush(
  messenger: admin.messaging.Messaging,
  tokens: string[],
  title: string,
  body: string,
  festivalId: string,
  festivalName: string,
  date: string,
): Promise<{ sent: number; failed: number }> {
  let sent = 0;
  let failed = 0;
  for (let i = 0; i < tokens.length; i += MAX_MULTICAST_TOKENS) {
    const batch = tokens.slice(i, i + MAX_MULTICAST_TOKENS);
    try {
      const res = await messenger.sendEachForMulticast({
        tokens: batch,
        notification: { title, body },
        data: {
          type: 'festival_wish',
          festivalId,
          festival: festivalName,
          date,
        },
      });
      sent += res.successCount;
      failed += res.failureCount;
      if (res.failureCount > 0) {
        res.responses.forEach((r, idx) => {
          if (!r.success) {
            logger.warn('festival push failed', {
              token: batch[idx]?.slice(0, 24),
              error: (r.error as Error | undefined)?.message ?? 'unknown',
            });
          }
        });
      }
    } catch (e) {
      logger.error('festival multicast batch failed', {
        error: e instanceof Error ? e.message : String(e),
      });
      failed += batch.length;
    }
  }
  return { sent, failed };
}

async function sendEmail(
  recipientEmail: string,
  recipientName: string,
  subject: string,
  bodyHtml: string,
): Promise<boolean> {
  if (!recipientEmail) return false;
  try {
    const res = await fetch(FESTIVAL_EMAIL_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        recipientEmail,
        recipientName,
        subject,
        bodyHtml,
      }),
    });
    if (res.status < 200 || res.status >= 300) {
      logger.warn('festival email endpoint returned error', {
        recipientEmail,
        status: res.status,
        body: await res.text(),
      });
      return false;
    }
    return true;
  } catch (e) {
    logger.error('festival email request failed', {
      recipientEmail,
      error: e instanceof Error ? e.message : String(e),
    });
    return false;
  }
}

/**
 * Processes a single tenant workspace. Isolated in its own try/catch so one
 * failing tenant never aborts the whole run.
 */
async function processTenant(
  firebaseProjectId: string,
  companyName: string,
  today: string,
): Promise<{
  venue: string;
  notifications: number;
  pushesSent: number;
  pushesFailed: number;
  emailsSent: number;
} | null> {
  const tenantApp = getTenantAdminApp(firebaseProjectId);
  const tenantDb = tenantApp.firestore();

  const settings = await loadFestivalSettings(tenantDb);
  if (!settings || settings.festivals.length === 0) {
    logger.info('festival: tenant has no enabled festival settings; skipping', {
      project: firebaseProjectId,
    });
    return null;
  }

  // Find festivals matching today OR today + advanceDays.
  const advance = settings.advanceDays > 0 ? settings.advanceDays : 0;
  const target = addDaysIso(today, advance);
  const targetSet = new Set([today, target]);
  const matched = settings.festivals.filter((f) => targetSet.has(f.date!));
  if (matched.length === 0) {
    logger.info('festival: no festival matches today or +advanceDays', {
      project: firebaseProjectId,
      today,
      advance,
    });
    return null;
  }

  // Idempotency: per-tenant marker keyed by festival+date, stored on the
  // settings doc itself (avoids an extra collection). With maxInstances:1 and
  // merge-style lastSent markers, an overlapping or manual re-run reads the
  // same state and skips anything already sent.
  const markerRef = tenantDb
      .collection('app_config')
      .doc('festival_settings');
  const toSend = new Map<string, FestivalEntry>();
  for (const f of matched) {
    const key = `${f.id || f.name}_${f.date}`;
    toSend.set(key, f);
  }

  const alreadySent = await loadAlreadySent(tenantDb);
  const pending = [...toSend.entries()].filter(([key]) => !alreadySent.has(key)).map(([, f]) => f);
  if (pending.length === 0) {
    logger.info('festival: all matching festivals already sent; skipping', {
      project: firebaseProjectId,
    });
    return null;
  }

  const employees = await collectTenantEmployees(tenantDb);
  if (employees.length === 0) {
    logger.info('festival: no employee records found; skipping', {
      project: firebaseProjectId,
    });
    return null;
  }

  const allTokens = [...new Set(employees.flatMap((e) => e.fcmTokens))];
  const messenger = tenantApp.messaging();
  const company = companyName.trim() || NotificationBrand;

  let notificationCount = 0;
  let pushSent = 0;
  let pushFailed = 0;
  let mailSent = 0;

  for (const festival of pending) {
    const festivalId = festival.id || festival.name!;
    const fname = festival.name!;
    const title = fillTemplates(
      settings.message?.title ?? 'Happy {festival}!',
      { festival: fname, companyName: company },
    );
    const body = fillTemplates(
      settings.message?.body ??
          '{companyName} wishes you a very Happy {festival}.',
      { festival: fname, companyName: company },
    );
    const emailSubject = fillTemplates(
      settings.message?.emailSubject ?? 'Happy {festival} from {companyName}',
      { festival: fname, companyName: company },
    );
    const emailBody = fillTemplates(
      settings.message?.emailBody ??
          'Dear {employeeName},<br/><br/>{companyName} wishes you a very Happy {festival}.',
      { festival: fname, companyName: company, employeeName: '' },
    );

    // 1) In-app notification docs — deterministic IDs for idempotency.
    const notifBatch = tenantDb.batch();
    let batchCount = 0;
    for (const emp of employees) {
      const docId = `festival_${festivalId}_${festival.date}_${safeId(emp.recipient)}`;
      const ref = tenantDb.collection('notifications').doc(docId);
      notifBatch.set(ref, {
        recipient: emp.recipient,
        type: 'Festival',
        title,
        content: fillTemplates(
          settings.message?.body ??
              '{companyName} wishes you a very Happy {festival}.',
          { festival: fname, companyName: company, employeeName: emp.employeeName },
        ),
        employeeName: emp.employeeName,
        status: 'Sent',
        suppressFirestorePush: true,
        allowFirestorePush: false,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        actionType: 'festival_wish',
        festival: fname,
        festivalId,
        festivalDate: festival.date,
        role: 'employee',
        companyName: company,
      });
      batchCount += 1;
      if (batchCount === 450) {
        await notifBatch.commit();
        batchCount = 0;
      }
    }
    if (batchCount > 0) await notifBatch.commit();
    notificationCount += employees.length;

    // 2) FCM push (multicast).
    if (allTokens.length > 0) {
      const r = await sendPush(
        messenger,
        allTokens,
        fillTemplates(
          settings.message?.title ?? title,
          { festival: fname, companyName: company },
        ),
        fillTemplates(
          settings.message?.body ?? body,
          { festival: fname, companyName: company },
        ),
        festivalId,
        fname,
        festival.date!,
      );
      pushSent += r.sent;
      pushFailed += r.failed;
    }

    // 3) Email — concurrency-limited so a large tenant doesn't blow the run
    // timeout or hammer the Vercel endpoint.
    const emailJobs = employees
        .filter((emp) => emp.email)
        .map((emp) => ({
          email: emp.email,
          name: emp.employeeName,
          subject: emailSubject,
          body: fillTemplates(emailBody, {
            festival: fname,
            companyName: company,
            employeeName: emp.employeeName,
          }),
        }));
    mailSent += await sendEmailsBounded(emailJobs, 10);
  }

  // Record the sent marker (merge all pending keys) AFTER successful sends so a
  // failed run leaves the marker unset and can be retried idempotently.
  if (pending.length > 0) {
    const lastSent: Record<string, string> = {};
    for (const f of pending) {
      lastSent[`${f.id || f.name}_${f.date}`] = new Date().toISOString();
    }
    await markerRef.set({ lastSent, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    logger.info('festival: marker recorded', { project: firebaseProjectId, lastSent });
  }

  return {
    venue: `${firebaseProjectId}/${company}`,
    notifications: notificationCount,
    pushesSent: pushSent,
    pushesFailed: pushFailed,
    emailsSent: mailSent,
  };
}

/** Sends a list of emails with bounded concurrency; returns the success count. */
async function sendEmailsBounded(
  jobs: { email: string; name: string; subject: string; body: string }[],
  concurrency: number,
): Promise<number> {
  let index = 0;
  let sent = 0;
  async function worker(): Promise<void> {
    while (index < jobs.length) {
      const job = jobs[index++];
      const ok = await sendEmail(job.email, job.name, job.subject, job.body);
      if (ok) sent += 1;
    }
  }
  const workers = Array.from({ length: Math.min(concurrency, jobs.length) }, worker);
  await Promise.all(workers);
  return sent;
}

/** Reads the `lastSent` map from festival_settings (merged field). */
async function loadAlreadySent(
  tenantDb: admin.firestore.Firestore,
): Promise<Set<string>> {
  const doc = await tenantDb.collection('app_config').doc('festival_settings').get();
  const lastSent = (doc.data()?.lastSent as Record<string, unknown> | undefined) ?? {};
  const keys = new Set<string>();
  for (const k of Object.keys(lastSent)) keys.add(k);
  return keys;
}

function safeId(value: string): string {
  const sanitized = value.replace(/[^A-Za-z0-9_-]/g, '_');
  return sanitized === '' ? 'employee' : sanitized;
}

/**
 * Daily festival-wishes scheduler. Object-form options are REQUIRED (the
 * bare-string form has a known firebase/firebase-functions#1734 bug that
 * creates a v1 scheduler URL → PERMISSION_DENIED at runtime).
 */
export const sendFestivalWishes = onSchedule(
  {
    schedule: '30 6 * * *',
    timeZone: 'Asia/Kolkata',
    region: 'us-central1',
    maxInstances: 1,
    memory: '512MiB',
    timeoutSeconds: 540,
    secrets: [serviceAccountJson],
  },
  async () => {
    const started = Date.now();
    const today = istToday();
    logger.info('sendFestivalWishes started', { today, started });

    const summary = {
      scannedTenants: 0,
      matchedTenants: 0,
      notifications: 0,
      pushesSent: 0,
      pushesFailed: 0,
      emailsSent: 0,
      errors: [] as string[],
    };

    const processedProjects = new Set<string>();

    try {
      const masterDb = getMasterAdmin().firestore();
      // Single-field query; filter fully-provisioned tenants in memory (avoids
      // a new composite index — mirrors auditOrphanedTenantProjects).
      const snap = await masterDb
          .collection('workspaces')
          .where('status', '==', 'active')
          .get();

      const results: NonNullable<Awaited<ReturnType<typeof processTenant>>>[] = [];

      for (const doc of snap.docs) {
        const data = doc.data();
        const config = data.firebaseConfig as Record<string, unknown> | undefined;
        const projectId = typeof data.firebaseProjectId === 'string'
          ? data.firebaseProjectId.trim()
          : typeof config?.projectId === 'string' ? config.projectId.trim() : '';
        const onboardingStatus =
          typeof data.onboardingStatus === 'string' ? data.onboardingStatus : '';
        const firebaseConfigured = data.firebaseConfigured === true
          || (config && typeof config.projectId === 'string');

        // In-memory "fully-provisioned" filter.
        if (!projectId || onboardingStatus !== 'ready' || !firebaseConfigured) {
          logger.info('festival: skipping non-provisioned workspace', {
            workspaceId: doc.id,
            projectId,
            onboardingStatus,
          });
          continue;
        }
        // Skip duplicate project bindings (defensive against the orphan-audit
        // duplicateBinding condition) to avoid double-processing a tenant.
        if (processedProjects.has(projectId)) {
          logger.warn('festival: duplicate project binding; skipping', {
            workspaceId: doc.id,
            projectId,
          });
          continue;
        }
        processedProjects.add(projectId);

        summary.scannedTenants += 1;
        try {
          const companyName = stringVal(data.companyName);
          const res = await processTenant(projectId, companyName, today);
          if (res) {
            summary.matchedTenants += 1;
            summary.notifications += res.notifications;
            summary.pushesSent += res.pushesSent;
            summary.pushesFailed += res.pushesFailed;
            summary.emailsSent += res.emailsSent;
            results.push(res);
          }
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          summary.errors.push(`${projectId}: ${msg}`);
          logger.error('festival: tenant processing failed', { projectId, error: msg });
        }
      }

      logger.info('sendFestivalWishes completed', {
        summary: {
          ...summary,
          durationMs: Date.now() - started,
          results,
        },
      });
    } catch (e) {
      logger.error('sendFestivalWishes aborted', {
        error: e instanceof Error ? e.message : String(e),
        durationMs: Date.now() - started,
      });
    }
  },
);
