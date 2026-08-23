/**
 * Shared helpers for raw-HTTP (onRequest) admin endpoints.
 *
 * These functions were converted from onCall to onRequest because the Flutter
 * Web client invokes them via raw fetch/http.post with an EXPLICIT
 * `Authorization: Bearer <idToken>` header (the callable SDK was observed
 * sending empty Authorization headers). onRequest does NOT provide automatic
 * Firebase Auth context, so callers must be verified manually via
 * `admin.auth().verifyIdToken()` — see [requireSuperAdmin].
 */

import * as admin from 'firebase-admin';
import { getMasterAdmin } from './firebaseAdmin';

/** Error type carrying an HTTP status + callable-style error code. */
export class HttpEndpointError extends Error {
  constructor(
    public readonly status: number,
    public readonly errorCode: string,
    message: string,
  ) {
    super(message);
    this.name = 'HttpEndpointError';
  }
}

/**
 * Resolves whether the request Origin is allowed. Returns the origin to echo
 * back, '*' for non-browser clients (no Origin header — curl, Dart IO, mobile),
 * or null when the origin must be rejected.
 *
 * Allow-list: localhost/127.0.0.1 (any port) for development, Firebase Hosting
 * domains of the master project for production, plus anything listed in the
 * CORS_ALLOWED_ORIGINS env var (comma-separated exact origins).
 */
export function resolveCorsOrigin(origin: string | undefined): string | null {
  if (!origin) return '*';

  const extra = (process.env.CORS_ALLOWED_ORIGINS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  const allowed: RegExp[] = [
    // Development: any localhost port
    /^https?:\/\/localhost(:\d+)?$/i,
    /^http:\/\/127\.0\.0\.1(:\d+)?$/i,
    // Production: master project Firebase Hosting domains
    /^https:\/\/trakradminsetup-28437([a-z0-9-]*\.){0,2}(web\.app|firebaseapp\.com)$/i,
    // Extra origins configured via environment
    ...extra.map(
      (o) => new RegExp(`^${o.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i'),
    ),
  ];

  return allowed.some((re) => re.test(origin)) ? origin : null;
}

/** Applies CORS response headers based on the request Origin. */
export function applyCors(req: { headers: { origin?: string } }, res: {
  setHeader(name: string, value: string): void;
}): void {
  const resolved = resolveCorsOrigin(req.headers.origin);
  res.setHeader('Access-Control-Allow-Origin', resolved ?? 'null');
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Max-Age', '3600');
}

/**
 * Verifies the `Authorization: Bearer <idToken>` header against the MASTER
 * project Auth and enforces the super_admin custom claim.
 *
 * Throws [HttpEndpointError] (401/403) on missing/invalid token or missing
 * claim. Returns the decoded ID token on success.
 */
export async function requireSuperAdmin(req: {
  headers: { authorization?: string | string[] },
}): Promise<admin.auth.DecodedIdToken> {
  const rawHeader = req.headers.authorization;
  const header = Array.isArray(rawHeader) ? rawHeader[0] : rawHeader;
  const match = /^Bearer\s+(.+)$/i.exec(header ?? '');
  if (!match) {
    throw new HttpEndpointError(
      401,
      'unauthenticated',
      'Missing Authorization: Bearer <Firebase ID token> header.',
    );
  }

  let decoded: admin.auth.DecodedIdToken;
  try {
    decoded = await getMasterAdmin().auth().verifyIdToken(match[1]);
  } catch (e) {
    throw new HttpEndpointError(
      401,
      'unauthenticated',
      `Invalid or expired ID token: ${(e as Error).message}`,
    );
  }

  if (!decoded.super_admin) {
    throw new HttpEndpointError(
      403,
      'permission-denied',
      'Only superadmins can call this endpoint. Missing super_admin custom claim.',
    );
  }

  return decoded;
}

/**
 * Extracts the payload from the request body. The Flutter client sends the
 * callable-protocol envelope `{"data": {...}}`, so unwrap `.data` when
 * present; a direct flat body is also accepted.
 */
export function extractData(body: unknown): Record<string, unknown> {
  if (body && typeof body === 'object') {
    const b = body as Record<string, unknown>;
    if (b.data && typeof b.data === 'object') {
      return b.data as Record<string, unknown>;
    }
    return b;
  }
  return {};
}

const STATUS_BY_CODE: Record<string, number> = {
  'invalid-argument': 400,
  'unauthenticated': 401,
  'permission-denied': 403,
  'not-found': 404,
  'failed-precondition': 412,
  'resource-exhausted': 429,
  'deadline-exceeded': 504,
};

/** Sends a callable-style error response: `{"error": {"code","message"}}`. */
export function sendError(res: {
  status(code: number): { json(value: unknown): void };
}, error: unknown): void {
  if (error instanceof HttpEndpointError) {
    res.status(error.status).json({
      error: { code: error.errorCode, message: error.message },
    });
    return;
  }
  // Map HttpsError-style codes thrown by business logic onto HTTP statuses.
  const anyErr = error as { code?: string; message?: string };
  const code = typeof anyErr?.code === 'string' ? anyErr.code : 'internal';
  const status = STATUS_BY_CODE[code] ?? 500;
  res.status(status).json({
    error: {
      code,
      message: anyErr?.message ?? 'Unknown server error',
    },
  });
}

/** Sends a callable-style success response: `{"result": {...}}`. */
export function sendResult(res: {
  status(code: number): { json(value: unknown): void };
}, result: unknown): void {
  res.status(200).json({ result });
}
