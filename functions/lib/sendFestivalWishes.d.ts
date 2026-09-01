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
/**
 * Daily festival-wishes scheduler. Object-form options are REQUIRED (the
 * bare-string form has a known firebase/firebase-functions#1734 bug that
 * creates a v1 scheduler URL → PERMISSION_DENIED at runtime).
 */
export declare const sendFestivalWishes: import("firebase-functions/v2/scheduler").ScheduleFunction;
//# sourceMappingURL=sendFestivalWishes.d.ts.map