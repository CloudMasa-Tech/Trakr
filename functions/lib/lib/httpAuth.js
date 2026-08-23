"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.HttpEndpointError = void 0;
exports.resolveCorsOrigin = resolveCorsOrigin;
exports.applyCors = applyCors;
exports.requireSuperAdmin = requireSuperAdmin;
exports.extractData = extractData;
exports.sendError = sendError;
exports.sendResult = sendResult;
const firebaseAdmin_1 = require("./firebaseAdmin");
/** Error type carrying an HTTP status + callable-style error code. */
class HttpEndpointError extends Error {
    status;
    errorCode;
    constructor(status, errorCode, message) {
        super(message);
        this.status = status;
        this.errorCode = errorCode;
        this.name = 'HttpEndpointError';
    }
}
exports.HttpEndpointError = HttpEndpointError;
/**
 * Resolves whether the request Origin is allowed. Returns the origin to echo
 * back, '*' for non-browser clients (no Origin header — curl, Dart IO, mobile),
 * or null when the origin must be rejected.
 *
 * Allow-list: localhost/127.0.0.1 (any port) for development, Firebase Hosting
 * domains of the master project for production, plus anything listed in the
 * CORS_ALLOWED_ORIGINS env var (comma-separated exact origins).
 */
function resolveCorsOrigin(origin) {
    if (!origin)
        return '*';
    const extra = (process.env.CORS_ALLOWED_ORIGINS || '')
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean);
    const allowed = [
        // Development: any localhost port
        /^https?:\/\/localhost(:\d+)?$/i,
        /^http:\/\/127\.0\.0\.1(:\d+)?$/i,
        // Production: master project Firebase Hosting domains
        /^https:\/\/trakradminsetup-28437([a-z0-9-]*\.){0,2}(web\.app|firebaseapp\.com)$/i,
        // Extra origins configured via environment
        ...extra.map((o) => new RegExp(`^${o.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i')),
    ];
    return allowed.some((re) => re.test(origin)) ? origin : null;
}
/** Applies CORS response headers based on the request Origin. */
function applyCors(req, res) {
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
async function requireSuperAdmin(req) {
    const rawHeader = req.headers.authorization;
    const header = Array.isArray(rawHeader) ? rawHeader[0] : rawHeader;
    const match = /^Bearer\s+(.+)$/i.exec(header ?? '');
    if (!match) {
        throw new HttpEndpointError(401, 'unauthenticated', 'Missing Authorization: Bearer <Firebase ID token> header.');
    }
    let decoded;
    try {
        decoded = await (0, firebaseAdmin_1.getMasterAdmin)().auth().verifyIdToken(match[1]);
    }
    catch (e) {
        throw new HttpEndpointError(401, 'unauthenticated', `Invalid or expired ID token: ${e.message}`);
    }
    if (!decoded.super_admin) {
        throw new HttpEndpointError(403, 'permission-denied', 'Only superadmins can call this endpoint. Missing super_admin custom claim.');
    }
    return decoded;
}
/**
 * Extracts the payload from the request body. The Flutter client sends the
 * callable-protocol envelope `{"data": {...}}`, so unwrap `.data` when
 * present; a direct flat body is also accepted.
 */
function extractData(body) {
    if (body && typeof body === 'object') {
        const b = body;
        if (b.data && typeof b.data === 'object') {
            return b.data;
        }
        return b;
    }
    return {};
}
const STATUS_BY_CODE = {
    'invalid-argument': 400,
    'unauthenticated': 401,
    'permission-denied': 403,
    'not-found': 404,
    'failed-precondition': 412,
    'resource-exhausted': 429,
    'deadline-exceeded': 504,
};
/** Sends a callable-style error response: `{"error": {"code","message"}}`. */
function sendError(res, error) {
    if (error instanceof HttpEndpointError) {
        res.status(error.status).json({
            error: { code: error.errorCode, message: error.message },
        });
        return;
    }
    // Map HttpsError-style codes thrown by business logic onto HTTP statuses.
    const anyErr = error;
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
function sendResult(res, result) {
    res.status(200).json({ result });
}
//# sourceMappingURL=httpAuth.js.map