#!/usr/bin/env python3
"""
Trakr CI security & quality gate  (Flutter + Firebase + Cloud Functions)

Python 3.8+, standard library only. Free: no paid services, no network needed
for the static stages. Heuristic pattern matching: it WILL have false
positives and misses, so use it as a gate, not as a replacement for review.

Stages (run all, or pick with --only):
  secrets    private keys, service-account JSON, live payment keys, tokens
  firebase   firestore.rules, database.rules.json, firebase.json, .htaccess
  android    manifest, release signing, committed keystores; iOS ATS
  functions  Cloud Functions without auth checks, wildcard CORS, risky calls
  code       Dart: cleartext http, TLS bypass, secrets in SharedPreferences
  workflows  GitHub Actions: permissions, unpinned actions, injection, FTP
  deps       flutter analyze, flutter test, npm audit, osv-scanner (if present)

Examples:
  python scripts/ci_security_check.py
  python scripts/ci_security_check.py --only secrets,firebase
  python scripts/ci_security_check.py --fail-on MEDIUM --strict
  python scripts/ci_security_check.py --write-baseline .security-baseline.json

Exit code: 1 if any NEW finding is at/above --fail-on (default HIGH), else 0.
Suppress a false positive by adding `nosec` in a comment on the same line.
"""
import argparse, fnmatch, hashlib, json, os, re, shutil, subprocess, sys
from dataclasses import dataclass, asdict, field
from datetime import datetime, timezone

SEV = {"INFO": 0, "LOW": 1, "MEDIUM": 2, "HIGH": 3, "CRITICAL": 4}
SKIP_DIRS = {".git", "node_modules", "build", ".dart_tool", ".gradle", ".idea",
             "Pods", ".pub-cache", ".agentview"}
SKIP_PREFIXES = ("functions/lib/", "android/build/", "ios/Pods/")
BIN_EXT = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".ico", ".ttf", ".otf", ".woff",
           ".woff2", ".zip", ".jar", ".so", ".dll", ".exe", ".pdf", ".mp3", ".mp4",
           ".keystore", ".jks", ".map", ".lock", ".wasm", ".icns"}
MAX_BYTES = 1_000_000


@dataclass
class Finding:
    sev: str
    stage: str
    rule: str
    file: str
    line: int
    msg: str
    fix: str = ""
    key: str = ""
    new: bool = True

    def fingerprint(self):
        return hashlib.sha1(f"{self.rule}|{self.file}|{self.key or self.msg}".encode()).hexdigest()[:16]


FINDINGS = []


def add(sev, stage, rule, file, line, msg, fix="", key=""):
    FINDINGS.append(Finding(sev, stage, rule, file, line, msg, fix, key))


# ----------------------------------------------------------------- file utils
def rel(root, p):
    return os.path.relpath(p, root).replace(os.sep, "/")


def walk(root):
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
        for f in files:
            p = os.path.join(d, f)
            r = rel(root, p)
            if r.startswith(SKIP_PREFIXES) or os.path.splitext(f)[1].lower() in BIN_EXT:
                continue
            try:
                if os.path.getsize(p) > MAX_BYTES:
                    continue
            except OSError:
                continue
            yield p, r


def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def mask(s, keep=4):
    s = s.strip()
    return s if len(s) <= keep * 2 else f"{s[:keep]}...{s[-keep:]}"


def is_test(r):
    return r.startswith(("test/", "integration_test/")) or "/test/" in r or r.endswith(("_test.dart", ".test.ts"))


PLACEHOLDER = re.compile(r"(x{4,}|a{6,}|your[_-]?|example|placeholder|changeme|dummy|not-the-real|fake|<.+>|\.\.\.|\$\{)", re.I)

# ------------------------------------------------------------------- 1 secrets
SECRET_RULES = [
    ("private-key", "CRITICAL", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----(?!\\\\n\.\.\.)"),
     "Private key committed", "Remove, rotate the key, purge it from git history."),
    ("aws-key", "CRITICAL", re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS access key id", "Rotate in IAM."),
    ("live-payment-key", "CRITICAL", re.compile(r"\b(?:sk_live|rk_live|rzp_live)_[A-Za-z0-9]{8,}"),
     "Live payment key", "Rotate in the provider dashboard; use secrets."),
    ("github-token", "CRITICAL", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b"), "GitHub token", "Revoke it."),
    ("slack-token", "HIGH", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"), "Slack token", "Revoke it."),
    ("generic-secret", "HIGH",
     re.compile(r"""(?i)\b(?:password|passwd|secret|api[_-]?key|auth[_-]?token|client[_-]secret)\b\s*[:=]\s*["']([^"'\s$]{8,})["']"""),
     "Hardcoded credential-like literal", "Move to env / Secret Manager / GitHub secret."),
]
GOOGLE_KEY = re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b")


def stage_secrets(root):
    seen_google = {}
    for p, r in walk(root):
        text = read(p)
        if not text:
            continue
        if re.search(r'"type"\s*:\s*"service_account"', text) and '"private_key"' in text and not is_test(r):
            add("CRITICAL", "secrets", "service-account-json", r, 1,
                "Firebase/GCP service-account JSON committed",
                "Delete, rotate the key in IAM, use Secret Manager / GitHub secrets.")
        for i, line in enumerate(text.splitlines(), 1):
            if "nosec" in line:
                continue
            for rule, sev, rx, msg, fix in SECRET_RULES:
                m = rx.search(line)
                if not m:
                    continue
                val = m.group(1) if m.groups() else m.group(0)
                if PLACEHOLDER.search(val) or PLACEHOLDER.search(line):
                    continue
                if rule == "generic-secret" and (re.fullmatch(r"[A-Z0-9_]+", val) or val.startswith("AIza")):
                    continue  # env-var / secret NAME, or a Firebase key (reported separately as INFO)
                if rule == "private-key" and is_test(r):
                    continue
                if rule == "generic-secret" and (is_test(r) or r.endswith(".md")):
                    sev = "LOW"
                if rule == "generic-secret" and re.search(r"(request|widget|\.text|controller|params)\b", line):
                    continue  # reading a value, not a literal secret
                add(sev, "secrets", rule, r, i, f"{msg}: {mask(val)}", fix, key=mask(val))
            for g in GOOGLE_KEY.findall(line):
                if not PLACEHOLDER.search(g) and not re.fullmatch(r"AIza(A+)", g):
                    seen_google.setdefault(g, []).append((r, i))
    for g, locs in seen_google.items():
        add("INFO", "secrets", "firebase-api-key", locs[0][0], locs[0][1],
            f"Google/Firebase API key {mask(g)} in {len(locs)} place(s). Public by design, "
            "but should be restricted.",
            "GCP Console > APIs & Services > Credentials: restrict by HTTP referrer / Android package + SHA-1, "
            "and to the Firebase APIs only. Security comes from Firestore rules, not key secrecy.", key=g)
    # secret-bearing files that should be git-ignored
    gi = read(os.path.join(root, ".gitignore"))
    for p, r in walk(root):
        base = os.path.basename(r)
        if re.fullmatch(r"(\.env(\..+)?|key\.properties|serviceAccountKey\.json|.*service-account.*\.json)", base) \
                and not base.endswith((".example", ".sample")):
            add("HIGH", "secrets", "secret-file", r, 1, f"Sensitive file present in repo: {base}",
                "Remove from the repo and add to .gitignore.")
    if "key.properties" not in gi and os.path.isdir(os.path.join(root, "android")):
        add("LOW", "secrets", "gitignore-keyprops", ".gitignore", 1,
            "key.properties (Android signing) is not git-ignored", "Add `key.properties` and `*.jks` to .gitignore.")


# ------------------------------------------------------------------ 2 firebase
def stage_firebase(root):
    for name in ("firestore.rules", "firestore.rules.master", "firebase.tenant.rules"):
        p = os.path.join(root, name)
        if os.path.exists(p):
            check_firestore_rules(name, read(p))
    for p, r in walk(root):
        if os.path.basename(r) == "database.rules.json":
            check_rtdb_rules(root, r, read(p))
    fb = os.path.join(root, "firebase.json")
    if os.path.exists(fb):
        check_firebase_json(read(fb))
    ht = os.path.join(root, "web", ".htaccess")
    if os.path.exists(ht):
        check_htaccess(read(ht))
    for p, r in walk(root):
        if r.startswith("web/") and re.search(r"(check|debug|test|diag)", os.path.basename(r), re.I) and r.endswith(".html"):
            add("LOW", "firebase", "web-diagnostic-page", r, 1,
                "Diagnostic page is shipped in the web build", "Exclude it from production builds or delete it.")


def check_firestore_rules(name, text):
    clean = re.sub(r"//[^\n]*", lambda m: " " * len(m.group(0)), text)  # keep offsets
    wide = {}
    for a in re.finditer(r"allow\s+([a-z, ]+):\s*if\s+([^;]+);", clean):
        ln = clean[:a.start()].count("\n") + 1
        if "nosec" in text.splitlines()[ln - 1]:
            continue
        paths = re.findall(r"match\s+(/[^\s{]+)", clean[:a.start()])
        path = paths[-1] if paths else "/"
        ops = [x.strip() for x in a.group(1).split(",")]
        cond = " ".join(a.group(2).split())
        writes = any(o in ("write", "create", "update", "delete") for o in ops)
        if cond == "true":
            sev = "CRITICAL" if writes else "MEDIUM"
            if not writes and "white_label" in path:
                sev = "INFO"
            add(sev, "firebase", "rules-open", name, ln,
                f"`allow {', '.join(ops)}: if true` on {path}: anyone on the internet, no sign-in needed",
                "Require auth, or keep public only for data that is safe to expose.", key=f"{path}|{cond}")
        elif cond == "signedIn()" and writes:
            wide[path] = ln
    if wide:
        names = ", ".join(sorted(wide))[:300]
        add("MEDIUM", "firebase", "rules-signedin-write", name, min(wide.values()),
            f"{len(wide)} collections writable by ANY signed-in user (no role / company check): {names}",
            "Scope writes with inCompany(companyId) or a permission check. If Email/Password sign-up is open, "
            "anyone can create an account and write here.", key="|".join(sorted(wide)))
    if not re.search(r"match\s+/\{document=\*\*\}\s*\{[^}]*allow\s+read,\s*write:\s*if\s+false", text, re.S):
        add("MEDIUM", "firebase", "rules-no-default-deny", name, 1, "No catch-all deny rule found",
            "Add `match /{document=**} { allow read, write: if false; }` last.")


def check_rtdb_rules(root, r, text):
    try:
        j = json.loads(text)["rules"]
    except Exception:
        add("LOW", "firebase", "rtdb-unparseable", r, 1, "database.rules.json could not be parsed")
        return
    deployed = "database" in read(os.path.join(root, "firebase.json"))
    for k in (".read", ".write"):
        v = str(j.get(k, "")).replace(" ", "")
        if v == "true":
            sev = "CRITICAL"
        elif v in ("auth!=null", "auth.uid!=null"):
            sev = "HIGH"
        else:
            continue
        if not deployed and sev != "CRITICAL":
            sev = "MEDIUM"
        add(sev, "firebase", "rtdb-root-open", r, 1,
            f"Realtime Database root `{k}: {j[k]}` grants every signed-in user access to the whole database"
            + ("" if deployed else " (file is not referenced in firebase.json, so it may be unused)"),
            "Remove root-level rules and grant access per path with ownership/company checks, "
            "or delete the file if RTDB is not used.", key=k)
    # `auth != null || ...` inside a read makes the other condition meaningless
    for m in re.finditer(r'"(\.read|\.write)"\s*:\s*"auth != null \|\|', text):
        add("MEDIUM", "firebase", "rtdb-or-bypass", r, text[:m.start()].count("\n") + 1,
            "`auth != null || <check>` : the OR makes the specific check redundant",
            "Use && so both conditions must hold.", key=str(m.start()))


def check_firebase_json(text):
    try:
        j = json.loads(text)
    except Exception:
        return
    hosting = j.get("hosting")
    if not hosting:
        return
    keys = {h["key"].lower() for blk in hosting.get("headers", []) for h in blk.get("headers", [])}
    for hdr, sev in (("strict-transport-security", "LOW"), ("referrer-policy", "LOW"),
                     ("permissions-policy", "LOW")):
        if hdr not in keys:
            add(sev, "firebase", "hosting-header", "firebase.json", 1, f"Hosting header `{hdr}` not set",
                "Add it under hosting.headers (only applies if you deploy to Firebase Hosting).", key=hdr)
    csp = [h["value"] for blk in hosting.get("headers", []) for h in blk.get("headers", [])
           if h["key"].lower() == "content-security-policy"]
    if csp and all(re.fullmatch(r"\s*frame-ancestors[^;]*;?\s*", c) for c in csp):
        add("LOW", "firebase", "csp-weak", "firebase.json", 1,
            "CSP only sets frame-ancestors; no script-src/connect-src restriction",
            "Add a real CSP (Flutter web needs 'wasm-unsafe-eval' and gstatic/firebase hosts).")


def check_htaccess(text):
    # Production is deployed over FTP to Apache, so .htaccess is what actually applies.
    for hdr, sev in (("Strict-Transport-Security", "MEDIUM"), ("X-Content-Type-Options", "LOW"),
                     ("Content-Security-Policy", "LOW"), ("Referrer-Policy", "LOW")):
        if not re.search(rf"Header\s+(always\s+)?(set|add)\s+{hdr}", text, re.I):
            add(sev, "firebase", "htaccess-header", "web/.htaccess", 1,
                f"Apache response header `{hdr}` not set in web/.htaccess",
                f'Add `Header always set {hdr} "<value>"` inside <IfModule mod_headers.c>.', key=hdr)
    if not re.search(r"RewriteCond.*HTTPS.*(off|!on)", text, re.I):
        add("LOW", "firebase", "htaccess-https", "web/.htaccess", 1,
            "No HTTP to HTTPS redirect found in .htaccess", "Add a RewriteRule forcing HTTPS.")


# ------------------------------------------------------------------- 3 android
def stage_android(root):
    for p, r in walk(root):
        t = read(p)
        base = os.path.basename(r)
        if base == "AndroidManifest.xml" and "/main/" in r:
            if re.search(r'android:debuggable\s*=\s*"true"', t):
                add("HIGH", "android", "debuggable", r, 1, "android:debuggable=true", "Remove it.")
            if re.search(r'usesCleartextTraffic\s*=\s*"true"', t):
                add("HIGH", "android", "cleartext", r, 1, "Cleartext HTTP traffic allowed",
                    "Set usesCleartextTraffic=false.")
            if not re.search(r'android:allowBackup\s*=\s*"false"', t):
                add("MEDIUM", "android", "allow-backup", r, 1,
                    "allowBackup is not disabled: app data (cached tokens/prefs) can be extracted via adb backup",
                    'Set android:allowBackup="false" (or define dataExtractionRules).')
        if base in ("build.gradle", "build.gradle.kts") and "/app/" in "/" + r:
            if re.search(r'release\s*\{[^}]*signingConfig\s*=?\s*(signingConfigs\.getByName\(\s*"debug"\s*\)|signingConfigs\.debug)', t, re.S):
                add("HIGH", "android", "release-debug-signing", r, 1,
                    "Release build is signed with the DEBUG key. Such an APK cannot go to Play Store and "
                    "is easy to repackage/impersonate",
                    "Create an upload keystore, reference it via key.properties (git-ignored) and CI secrets.")
            if re.search(r'release\s*\{', t) and not re.search(r'isMinifyEnabled\s*=\s*true|minifyEnabled\s+true', t):
                add("LOW", "android", "no-minify", r, 1, "Release build has no R8 minify/obfuscation",
                    "Enable isMinifyEnabled and build with --obfuscate --split-debug-info.")
        if base.endswith((".jks", ".keystore")) or r.endswith("key.properties"):
            add("CRITICAL", "android", "keystore-committed", r, 1, "Signing keystore/properties committed", "Remove, rotate.")
        if base == "Info.plist" and re.search(r"NSAllowsArbitraryLoads</key>\s*<true", t):
            add("HIGH", "android", "ios-ats-off", r, 1, "iOS App Transport Security disabled", "Remove NSAllowsArbitraryLoads.")
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for f in fn:
            if f.endswith((".jks", ".keystore")):
                add("CRITICAL", "android", "keystore-committed", rel(root, os.path.join(dp, f)), 1,
                    "Signing keystore committed", "Remove and rotate.")


# ----------------------------------------------------------------- 4 functions
def stage_functions(root):
    d = os.path.join(root, "functions", "src")
    for dp, dn, fn in os.walk(d):
        for f in fn:
            if not f.endswith(".ts"):
                continue
            p = os.path.join(dp, f)
            r, t = rel(root, p), read(p)
            for m in re.finditer(r"export const (\w+)\s*=\s*(onCall|onRequest)\(", t):
                name, kind = m.groups()
                body = t[m.start():]
                nxt = re.search(r"\nexport const ", body[10:])
                body = body[: nxt.start() + 10] if nxt else body
                ln = t[:m.start()].count("\n") + 1
                if kind == "onCall" and not re.search(r"request\.auth|\.auth\?\.|assertAuth|requireAuth|context\.auth", body + t):
                    add("HIGH", "functions", "oncall-no-auth", r, ln, f"onCall `{name}` never checks request.auth",
                        "Throw HttpsError('unauthenticated') unless request.auth is present.", key=name)
                if kind == "onRequest" and not re.search(r"verifyIdToken|verifyToken|timingSafeEqual|x-signature|HMAC", t, re.I):
                    add("HIGH", "functions", "onrequest-no-auth", r, ln,
                        f"onRequest `{name}` has no token/signature verification (HTTP endpoints are public)",
                        "Verify a Firebase ID token (admin.auth().verifyIdToken) or a webhook signature.", key=name)
            for i, line in enumerate(t.splitlines(), 1):
                if "nosec" in line:
                    continue
                if re.search(r"cors\s*:\s*true|Access-Control-Allow-Origin['\"]?\s*[,:]\s*['\"]\*", line):
                    add("MEDIUM", "functions", "wildcard-cors", r, i, "Wildcard CORS", "Allow-list your real web origin(s).", key=str(i))
                if re.search(r"\beval\(|new Function\(|child_process|execSync\(", line):
                    add("HIGH", "functions", "dangerous-exec", r, i, "eval / shell execution", "Avoid or strictly validate input.", key=str(i))
                if re.search(r"console\.(log|info|debug)\(.*(token|password|secret|private_key|authorization)", line, re.I):
                    add("MEDIUM", "functions", "log-secret", r, i, "Possible secret/token written to logs",
                        "Do not log credentials; Cloud Logging is readable by project viewers.", key=str(i))
                if re.search(r"invoker\s*:\s*['\"]public['\"]", line):
                    add("LOW", "functions", "public-invoker", r, i, "Function invokable by anyone (IAM)", "Fine only if auth is checked in code.", key=str(i))
    for f in os.listdir(os.path.join(root, "functions")) if os.path.isdir(os.path.join(root, "functions")) else []:
        if re.match(r"test-.*\.js$", f):
            add("LOW", "functions", "stray-test-script", f"functions/{f}", 1,
                "Ad-hoc test script lives in the functions/ source folder (may get deployed)",
                "Move to scripts/ or add to .gcloudignore / firebase.json functions.ignore.")


# --------------------------------------------------------------------- 5 code
def stage_code(root):
    for p, r in walk(root):
        if not r.endswith(".dart") or is_test(r):
            continue
        t = read(p)
        lines = t.splitlines()
        for i, line in enumerate(lines, 1):
            if "nosec" in line or line.strip().startswith("//"):
                continue
            if re.search(r"""['"]http://(?!localhost|127\.|10\.0\.2\.2|www\.w3\.org|schemas\.)""", line):
                add("MEDIUM", "code", "cleartext-url", r, i, "Cleartext http:// URL", "Use https://.", key=line.strip())
            if "badCertificateCallback" in line:
                add("HIGH", "code", "tls-bypass", r, i, "TLS certificate validation bypassed", "Remove it.", key=line.strip())
            if re.search(r"\b(print|debugPrint)\(.*\$\{?[\w.?!]*(password|token|secret|apiKey|credential)", line, re.I):
                add("MEDIUM", "code", "log-secret", r, i, "Credential/token printed to logs",
                    "Remove, or guard with kDebugMode and never print secrets.", key=line.strip())
            if re.search(r"prefs?\.set(String|StringList)\(\s*['\"][^'\"]*(token|password|secret|credential)", line, re.I):
                add("MEDIUM", "code", "prefs-secret", r, i,
                    "Secret/token stored in SharedPreferences (plain text on device / localStorage on web)",
                    "Use flutter_secure_storage for secrets on mobile.", key=line.strip())
            if re.search(r"\b(innerHtml|unsafeHtml|\.setInnerHtml)\b", line):
                add("LOW", "code", "html-injection", r, i, "Raw HTML injection (XSS risk on web)", "Sanitize or avoid.", key=line.strip())
        if re.search(r"(?i)(qr|token|nonce|otp)", t) and re.search(r"\bRandom\(\s*[^)]*\)(?!\.secure)", t) \
                and "Random.secure" not in t:
            m = re.search(r"\bRandom\(", t)
            add("MEDIUM", "code", "weak-random", r, t[:m.start()].count("\n") + 1,
                "Non-cryptographic Random() in a file that handles tokens/QR codes (predictable values)",
                "Use Random.secure() for anything an attacker could guess.", key=r)


# ------------------------------------------------------------------ 6 workflows
def stage_workflows(root):
    wf = os.path.join(root, ".github", "workflows")
    if not os.path.isdir(wf):
        return
    for f in sorted(os.listdir(wf)):
        if not f.endswith((".yml", ".yaml")):
            continue
        r, t = f".github/workflows/{f}", read(os.path.join(wf, f))
        if not re.search(r"^permissions:", t, re.M):
            add("MEDIUM", "workflows", "no-permissions", r, 1, "No `permissions:` block (token gets broad default rights)",
                "Add `permissions: contents: read` at top level.")
        if "pull_request_target" in t:
            add("HIGH", "workflows", "pr-target", r, 1, "pull_request_target: fork code can run with secrets",
                "Use pull_request, or never check out untrusted code.")
        for i, line in enumerate(t.splitlines(), 1):
            u = re.search(r"uses:\s*([\w.-]+/[\w./-]+)@(\S+)", line)
            if u and not re.fullmatch(r"[0-9a-f]{40}", u.group(2)):
                third = not u.group(1).startswith(("actions/", "github/"))
                add("MEDIUM" if third else "LOW", "workflows", "unpinned-action", r, i,
                    f"{u.group(1)}@{u.group(2)} is not pinned to a commit SHA",
                    "Pin to the full commit SHA (Dependabot can keep it updated).", key=u.group(1))
            if re.search(r"run:.*\$\{\{\s*github\.event\.(issue|pull_request|comment|head_commit|commits)", line):
                add("HIGH", "workflows", "script-injection", r, i, "Untrusted event data interpolated into a shell command",
                    "Pass via env: and quote it.", key=str(i))
            if re.search(r"protocol:\s*ftp\s*$", line):
                add("HIGH", "workflows", "plain-ftp", r, i, "Plain FTP deploy: credentials and files sent unencrypted",
                    "Use protocol: ftps or SFTP.", key=str(i))
            if re.search(r"dangerous-clean-slate:\s*true", line):
                add("LOW", "workflows", "clean-slate", r, i, "FTP deploy wipes the server directory", "Be sure that is intended.", key=str(i))


# ---------------------------------------------------------------------- 7 deps
def run(cmd, cwd, timeout=900):
    try:
        c = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return c.returncode, (c.stdout or "") + (c.stderr or "")
    except Exception as e:
        return 127, str(e)


def stage_deps(root, strict):
    skipped = []

    def skip(what, why):
        skipped.append(what)
        add("HIGH" if strict else "INFO", "deps", "stage-skipped", what, 0, f"{what} skipped: {why}",
            "Run in CI where the tool/network is available.", key=what)

    if shutil.which("flutter"):
        code, out = run(["flutter", "analyze", "--no-pub"], root)
        errs = [l for l in out.splitlines() if re.match(r"\s*error\s", l)]
        for l in errs[:50]:
            add("MEDIUM", "deps", "flutter-analyze", "flutter analyze", 0, l.strip()[:200], key=l.strip())
        code, out = run(["flutter", "test"], root)
        if code != 0:
            add("HIGH", "deps", "flutter-test", "flutter test", 0, "Unit/widget tests failed: " + out.strip().splitlines()[-1][:200] if out.strip() else "tests failed")
    else:
        skip("flutter analyze/test", "flutter not installed")

    for sub in ("functions", "scripts", "."):
        d = os.path.join(root, sub)
        if not os.path.exists(os.path.join(d, "package.json")):
            continue
        label = f"npm audit ({sub})"
        if not os.path.exists(os.path.join(d, "package-lock.json")):
            add("LOW", "deps", "no-lockfile", f"{sub}/package.json", 1,
                "No package-lock.json: installs are not reproducible and `npm audit` cannot run",
                "Run `npm install` and commit package-lock.json.", key=sub)
            continue
        if not shutil.which("npm"):
            skip(label, "npm not installed")
            continue
        code, out = run(["npm", "audit", "--json", "--omit=dev"], d)
        try:
            vulns = json.loads(out).get("vulnerabilities", {})
        except Exception:
            skip(label, "no usable output (offline?)")
            continue
        smap = {"critical": "CRITICAL", "high": "HIGH", "moderate": "MEDIUM", "low": "LOW"}
        for n, v in vulns.items():
            add(smap.get(v.get("severity"), "LOW"), "deps", "npm-vuln", f"{sub}/package-lock.json", 1,
                f"{n}: {v.get('severity')} vulnerability" + (" (fix available)" if v.get("fixAvailable") else ""),
                "npm audit fix", key=f"{sub}:{n}")

    lock = os.path.join(root, "pubspec.lock")
    if os.path.exists(lock):
        if shutil.which("osv-scanner"):
            code, out = run(["osv-scanner", "--lockfile", lock, "--format", "json"], root)
            try:
                for res in json.loads(out).get("results", []):
                    for pk in res.get("packages", []):
                        for v in pk.get("vulnerabilities", []):
                            add("HIGH", "deps", "pub-vuln", "pubspec.lock", 1,
                                f"{pk['package']['name']} {pk['package']['version']}: {v.get('id')} {v.get('summary','')[:100]}",
                                "flutter pub upgrade <pkg>", key=v.get("id", ""))
            except Exception:
                skip("osv-scanner (pubspec.lock)", "no usable output")
        else:
            skip("osv-scanner (pubspec.lock)", "osv-scanner not installed (the workflow runs it separately)")
        for m in re.finditer(r"^\s{2}(\S+):\n(?:\s{4}.*\n)*?\s{4}source: git", read(lock), re.M):
            add("LOW", "deps", "git-dependency", "pubspec.lock", 1, f"Package {m.group(1)} comes from a git source",
                "Pin to a commit/tag and review it.", key=m.group(1))



# ------------------------------------------------------------ visual summary
STAGE_TITLES = {"secrets": "Secrets", "firebase": "Firebase rules & hosting", "android": "Android / iOS",
                "functions": "Cloud Functions", "code": "Dart code", "workflows": "GitHub workflows",
                "deps": "Dependencies & tests"}


def stage_status(stage, fail_on):
    fs = [f for f in FINDINGS if f.stage == stage]
    if any(f.new and SEV[f.sev] >= SEV[fail_on] for f in fs):
        return "FAIL"
    if any(f.new and SEV[f.sev] >= SEV["MEDIUM"] for f in fs):
        return "WARN"
    return "PASS"


PEN = {"CRITICAL": 40, "HIGH": 20, "MEDIUM": 5, "LOW": 1, "INFO": 0}
SHORT = {"secrets": "SECRETS", "firebase": "FIREBASE", "android": "ANDROID/iOS", "functions": "FUNCTIONS",
         "code": "DART CODE", "workflows": "WORKFLOWS", "deps": "DEPENDENCIES"}


def stage_score(stage, ignore_high=False):
    pen = sum(PEN[f.sev] for f in FINDINGS if f.stage == stage and f.new
              and not (ignore_high and SEV[f.sev] >= SEV["HIGH"]))
    return max(0, 100 - pen)


def overall_score(chosen, ignore_high=False):
    sc = [stage_score(s, ignore_high) for s in chosen]
    return round(0.5 * sum(sc) / len(sc) + 0.5 * min(sc)) if sc else 100  # weighted toward weakest area


def box_summary(chosen, fail_on):
    import textwrap
    color = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
    RED, YEL, GRN, DIM, BOLD, CY = "31", "33", "32", "2", "1", "36"

    def c(t, code):
        return f"\033[{code}m{t}\033[0m" if color else t

    def sc_col(v):
        return GRN if v >= 85 else (YEL if v >= 60 else RED)

    width = max(70, min(shutil.get_terminal_size((100, 20)).columns - 2, 100))
    out = [""]
    out.append(c(f"  Security Audit: {os.path.basename(os.getcwd())}", f"{BOLD};{CY}"))
    out.append(c(f"  {datetime.now().strftime('%Y-%m-%d')}  |  {len(chosen)} checks  |  {len(FINDINGS)} findings", DIM))
    out.append("")

    now, after = overall_score(chosen), overall_score(chosen, ignore_high=True)
    inner = 56
    out.append("  \u256d" + "\u2500" * inner + "\u256e")
    out.append("  \u2502" + " " * inner + "\u2502")
    left = f"  SECURITY SCORE: {now}/100"
    right = f"AFTER FIXING HIGH+: {after}/100  "
    line = left + " " * (inner - len(left) - len(right)) + right
    out.append("  \u2502" + line.replace(f"{now}/100", c(f"{now}/100", f"{BOLD};{sc_col(now)}"))
               .replace(f"{after}/100", c(f"{after}/100", f"{BOLD};{sc_col(after)}")) + "\u2502")
    out.append("  \u2502" + " " * inner + "\u2502")
    out.append("  \u2570" + "\u2500" * inner + "\u256f")
    out.append("")

    # tiles, 4 per row
    tw = 17
    for i in range(0, len(chosen), 4):
        row = chosen[i:i + 4]
        lines = ["", "", "", "", ""]
        for st in row:
            v, status = stage_score(st), stage_status(st, fail_on)
            n = len([f for f in FINDINGS if f.stage == st and f.new and SEV[f.sev] >= SEV["LOW"]])
            col = {"PASS": GRN, "WARN": YEL, "FAIL": RED}[status]
            lines[0] += "  \u256d" + "\u2500" * tw + "\u256e"
            lines[1] += "  \u2502" + SHORT[st].center(tw) + "\u2502"
            lines[2] += "  \u2502" + c(str(v).center(tw), f"{BOLD};{sc_col(v)}") + "\u2502"
            lines[3] += "  \u2502" + c(f"[ {status} ]".center(tw), f"{BOLD};{col}") + "\u2502"
            lines[4] += "  \u2502" + f"{n} issue(s)".center(tw) + "\u2502"
        out += lines
        out.append("  " + ("\u2570" + "\u2500" * tw + "\u256f  ") * len(row))
        out.append("")

    urgent = [f for f in FINDINGS if f.new and SEV[f.sev] >= SEV["HIGH"]]
    out.append(c("  \u25cf Critical & High findings", f"{BOLD};{RED}") + c("   FIX THIS WEEK", RED) if urgent
               else c("  \u25cf No critical or high findings", f"{BOLD};{GRN}"))
    out.append("")
    cw = width - 6
    for f in urgent:
        tag = c(f" {f.sev} ", f"{BOLD};{RED}")
        loc = f"{f.file}:{f.line}" if f.line else f.file
        out.append("  \u250c" + "\u2500" * cw + "\u2510")
        for j, l in enumerate(textwrap.wrap(f.msg, cw - 12) or [""]):
            head = f"{tag}" if j == 0 else " " * (len(f.sev) + 2)
            vis = len(f.sev) + 2
            out.append("  \u2502 " + head + " " + l.ljust(cw - vis - 3) + " \u2502")
        out.append("  \u2502 " + c(loc[:cw - 3].ljust(cw - 2), DIM) + " \u2502")
        if f.fix:
            out.append("  \u2502 " + " " * (cw - 2) + " \u2502")
            wrapped = textwrap.wrap("Fix: " + f.fix, cw - 4)
            for l in wrapped:
                txt = l.ljust(cw - 2)
                out.append("  \u2502 " + (c(txt[:4], BOLD) + txt[4:] if l.startswith("Fix:") else txt) + " \u2502")
        out.append("  \u2514" + "\u2500" * cw + "\u2518")
    med = [f for f in FINDINGS if f.new and f.sev == "MEDIUM"]
    if med:
        out.append("")
        out.append(c(f"  \u25cf Medium findings ({len(med)}): plan these", f"{BOLD};{YEL}"))
        for f in med:
            loc = f"{f.file}:{f.line}" if f.line else f.file
            out.append("   - " + (f.msg[:width - 12] + ("..." if len(f.msg) > width - 12 else "")))
            out.append(c(f"       {loc}", DIM))
    low = len([f for f in FINDINGS if f.new and f.sev == "LOW"])
    if low:
        out.append("")
        out.append(c(f"  + {low} low-severity item(s): see the full report", DIM))
    overall = "FAIL" if any(stage_status(x, fail_on) == "FAIL" for x in chosen) else "PASS"
    out.append("")
    out.append("  " + (c(" RESULT: FAILED ", f"{BOLD};41;37") + "  fix the HIGH/CRITICAL items above" if overall == "FAIL"
                       else c(" RESULT: PASSED ", f"{BOLD};42;30")))
    out.append("")
    return "\n".join(out)


def html_report(chosen, fail_on, counts, path):
    import html as H
    cls = {"PASS": "#1a7f37", "WARN": "#b7791f", "FAIL": "#cf222e"}
    sevc = {"CRITICAL": "#8b0000", "HIGH": "#cf222e", "MEDIUM": "#b7791f", "LOW": "#0969da", "INFO": "#6e7781"}
    overall = "FAIL" if any(stage_status(s, fail_on) == "FAIL" for s in chosen) else "PASS"
    cards = ""
    for st in chosen:
        status = stage_status(st, fail_on)
        n = [f for f in FINDINGS if f.stage == st and SEV[f.sev] >= SEV["LOW"]]
        cards += (f'<div class="card" style="border-top:6px solid {cls[status]}"><div class="t">{H.escape(STAGE_TITLES[st])}</div>'
                  f'<div class="s" style="color:{cls[status]}">{status}</div><div class="n">{len(n)} issue(s)</div></div>')
    chips = "".join(f'<span class="chip" style="background:{sevc[k]}">{k} {v}</span>' for k, v in reversed(list(counts.items())))
    rows = ""
    for f in FINDINGS:
        loc = f"{f.file}:{f.line}" if f.line else f.file
        rows += (f'<tr><td><b style="color:{sevc[f.sev]}">{f.sev}</b></td><td>{f.stage}</td>'
                 f'<td class="m">{H.escape(loc)}</td><td>{H.escape(f.msg)}</td><td>{H.escape(f.fix)}</td></tr>')
    doc = f"""<!doctype html><html><head><meta charset="utf-8"><title>Trakr security report</title>
<style>body{{font-family:system-ui,sans-serif;margin:0;background:#f6f8fa;color:#1f2328}}
.wrap{{max-width:1100px;margin:auto;padding:24px}}
.banner{{background:{cls[overall]};color:#fff;border-radius:10px;padding:18px 24px;font-size:22px;font-weight:700}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:14px;margin:18px 0}}
.card{{background:#fff;border-radius:8px;padding:14px;box-shadow:0 1px 3px #0002}}
.t{{font-size:14px;color:#57606a}}.s{{font-size:28px;font-weight:800;margin:6px 0}}.n{{font-size:13px;color:#57606a}}
.chip{{color:#fff;border-radius:12px;padding:3px 10px;margin-right:6px;font-size:13px}}
table{{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;overflow:hidden;font-size:13px;margin-top:16px}}
th,td{{text-align:left;padding:8px 10px;border-bottom:1px solid #eaeef2;vertical-align:top}}th{{background:#eaeef2}}
.m{{font-family:monospace;font-size:12px}}</style></head><body><div class="wrap">
<div class="banner">{'FAILED: HIGH/CRITICAL issues need fixing' if overall == 'FAIL' else 'PASSED'}
<div style="font-size:13px;font-weight:400;margin-top:4px">Gate: fail on {fail_on}+ &middot; {datetime.now().strftime('%d %b %Y %H:%M')}</div></div>
<div class="grid">{cards}</div><div>{chips}</div>
<table><tr><th>Severity</th><th>Check</th><th>Location</th><th>Finding</th><th>How to fix</th></tr>{rows}</table>
</div></body></html>"""
    open(path, "w", encoding="utf-8").write(doc)


# ----------------------------------------------------------------------- main
STAGES = ["secrets", "firebase", "android", "functions", "code", "workflows", "deps"]


def main():
    ap = argparse.ArgumentParser(description="Trakr CI security gate")
    ap.add_argument("--root", default=".")
    ap.add_argument("--only", default="", help="comma list of stages: " + ",".join(STAGES))
    ap.add_argument("--fail-on", default="HIGH", choices=list(SEV))
    ap.add_argument("--baseline", default="", help="only fail on findings not in this file")
    ap.add_argument("--write-baseline", default="")
    ap.add_argument("--strict", action="store_true", help="skipped deps stages count as HIGH")
    ap.add_argument("--verbose", action="store_true", help="also print the flat list of every finding")
    ap.add_argument("--report-dir", default="security-reports")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    chosen = [s for s in (a.only.split(",") if a.only else STAGES) if s]
    bad = [s for s in chosen if s not in STAGES]
    if bad:
        ap.error(f"unknown stage(s): {bad}")

    fns = {"secrets": stage_secrets, "firebase": stage_firebase, "android": stage_android,
           "functions": stage_functions, "code": stage_code, "workflows": stage_workflows}
    for s in chosen:
        print(f"> stage: {s}", flush=True)
        stage_deps(root, a.strict) if s == "deps" else fns[s](root)

    if a.baseline and os.path.exists(a.baseline):
        known = set(json.load(open(a.baseline)).get("fingerprints", []))
        for f in FINDINGS:
            f.new = f.fingerprint() not in known
    if a.write_baseline:
        json.dump({"created": datetime.now(timezone.utc).isoformat(),
                   "fingerprints": sorted({f.fingerprint() for f in FINDINGS})}, open(a.write_baseline, "w"), indent=1)
        print(f"Baseline written: {a.write_baseline} ({len(FINDINGS)} findings)")

    FINDINGS.sort(key=lambda f: (-SEV[f.sev], f.stage, f.file, f.line))
    os.makedirs(a.report_dir, exist_ok=True)
    counts = {s: sum(1 for f in FINDINGS if f.sev == s) for s in SEV}
    gate = [f for f in FINDINGS if f.new and SEV[f.sev] >= SEV[a.fail_on]]
    with open(os.path.join(a.report_dir, "report.json"), "w") as fh:
        json.dump({"generated": datetime.now(timezone.utc).isoformat(), "counts": counts,
                   "findings": [dict(asdict(f), fingerprint=f.fingerprint()) for f in FINDINGS]}, fh, indent=1)
    md = ["# Trakr security report", "",
          " | ".join(f"**{k}** {v}" for k, v in reversed(list(counts.items()))), "",
          f"Gate: fail on **{a.fail_on}+** (new findings only if a baseline is used): "
          + ("**FAIL**" if gate else "**PASS**"), "",
          "| Sev | Stage | Location | Finding | Fix |", "|---|---|---|---|---|"]
    for f in FINDINGS:
        loc = f"`{f.file}:{f.line}`" if f.line else f"`{f.file}`"
        md.append(f"| {f.sev}{'' if f.new else ' (baseline)'} | {f.stage} | {loc} | "
                  f"{f.msg.replace('|', '/')} | {f.fix.replace('|', '/')} |")
    report = "\n".join(md)
    open(os.path.join(a.report_dir, "report.md"), "w").write(report)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        open(os.environ["GITHUB_STEP_SUMMARY"], "a").write(report + "\n")

    print()
    for f in FINDINGS:
        if a.verbose and (SEV[f.sev] >= SEV["LOW"] or f.stage == "deps"):
            print(f"[{f.sev:8}] {f.file}:{f.line}  {f.msg}")
            if os.environ.get("GITHUB_ACTIONS") and SEV[f.sev] >= SEV["MEDIUM"] and f.line:
                lvl = "error" if SEV[f.sev] >= SEV["HIGH"] else "warning"
                print(f"::{lvl} file={f.file},line={f.line},title={f.rule}::{f.msg}")
    html_report(chosen, a.fail_on, counts, os.path.join(a.report_dir, "report.html"))
    print(box_summary(chosen, a.fail_on))
    print(f"  Full report: {a.report_dir}/report.html (open in browser), report.md, report.json\n")
    return 1 if gate else 0


if __name__ == "__main__":
    sys.exit(main())
