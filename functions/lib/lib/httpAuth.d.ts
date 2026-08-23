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
/** Error type carrying an HTTP status + callable-style error code. */
export declare class HttpEndpointError extends Error {
    readonly status: number;
    readonly errorCode: string;
    constructor(status: number, errorCode: string, message: string);
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
export declare function resolveCorsOrigin(origin: string | undefined): string | null;
/** Applies CORS response headers based on the request Origin. */
export declare function applyCors(req: {
    headers: {
        origin?: string;
    };
}, res: {
    setHeader(name: string, value: string): void;
}): void;
/**
 * Verifies the `Authorization: Bearer <idToken>` header against the MASTER
 * project Auth and enforces the super_admin custom claim.
 *
 * Throws [HttpEndpointError] (401/403) on missing/invalid token or missing
 * claim. Returns the decoded ID token on success.
 */
export declare function requireSuperAdmin(req: {
    headers: {
        authorization?: string | string[];
    };
}): Promise<admin.auth.DecodedIdToken>;
/**
 * Extracts the payload from the request body. The Flutter client sends the
 * callable-protocol envelope `{"data": {...}}`, so unwrap `.data` when
 * present; a direct flat body is also accepted.
 */
export declare function extractData(body: unknown): Record<string, unknown>;
/** Sends a callable-style error response: `{"error": {"code","message"}}`. */
export declare function sendError(res: {
    status(code: number): {
        json(value: unknown): void;
    };
}, error: unknown): void;
/** Sends a callable-style success response: `{"result": {...}}`. */
export declare function sendResult(res: {
    status(code: number): {
        json(value: unknown): void;
    };
}, result: unknown): void;
//# sourceMappingURL=httpAuth.d.ts.map