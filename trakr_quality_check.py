#!/usr/bin/env python3
"""
Trakr quality gate: performance, security, tech SEO, AI-search readiness, local SEO,
schema, website functional checks, tests and critical-bug scan, with a 0-100 score.

Python 3.8+, standard library only (no installs). Works in two modes:
  * LIVE   (--url https://your-site.com): fetches the deployed site over HTTP
  * STATIC (no --url): reads the built/source web folder (build/web or web)
Repo checks (unit tests, analyze, empty catch blocks, security scan) run in both.

Examples
  python3 trakr_quality_check.py                              # static, repo + web/ files
  python3 trakr_quality_check.py --url https://trakr.example.com --city Pondicherry
  python3 trakr_quality_check.py --url https://trakr.example.com --fail-under 70 --paths /login
  python3 trakr_quality_check.py --only security,tech_seo
  python3 trakr_quality_check.py --list-rules            # print every rule
  python3 trakr_quality_check.py --list-rules --md > RULES.md

Exit code 1 when the overall score is below --fail-under, or any CRITICAL rule fails.
"""
import argparse, gzip, glob, html as H, json, os, re, shutil, subprocess, sys, tempfile, time
import urllib.error, urllib.parse, urllib.request, urllib.robotparser
import xml.etree.ElementTree as ET
from datetime import datetime
from html.parser import HTMLParser

UA = "TrakrQualityBot/1.0"
SEV_W = {"critical": 5, "high": 3, "medium": 2, "low": 1}
CREDIT = {"PASS": 1.0, "WARN": 0.5, "FAIL": 0.0}

CATS = {  # key: (title, weight)
    "security": ("Security", 15), "performance": ("Performance", 12), "tech_seo": ("Technical SEO", 18),
    "ai_search": ("AI search (GEO)", 10), "local_seo": ("Local SEO", 8), "schema": ("Schema / structured data", 10),
    "functional": ("Website functional", 8), "testing": ("Unit & functional tests", 11),
    "bugs": ("Critical bugs", 8),
}
TILE = {"security": "Security", "performance": "Performance", "tech_seo": "Technical SEO", "ai_search": "AI search", "local_seo": "Local SEO",
        "schema": "Schema", "functional": "Website", "testing": "Tests", "bugs": "Critical bugs"}
GOOGLE_SEO_MIX = {"tech_seo": 40, "schema": 20, "performance": 15, "local_seo": 15, "functional": 10}

# id, category, severity, title, how to fix
RULES = [
 ("SEC-01", "security", "high", "HTTPS enforced (http redirects to https)", "Redirect all http:// traffic to https:// in .htaccess / hosting."),
 ("SEC-02", "security", "medium", "Strict-Transport-Security (HSTS) header", 'Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"'),
 ("SEC-03", "security", "medium", "Content-Security-Policy header", "Add a CSP (Flutter web needs 'wasm-unsafe-eval' and gstatic/firebase hosts)."),
 ("SEC-04", "security", "low", "X-Content-Type-Options: nosniff", 'Header always set X-Content-Type-Options "nosniff"'),
 ("SEC-05", "security", "medium", "Clickjacking protection (X-Frame-Options or frame-ancestors)", 'Header always set X-Frame-Options "SAMEORIGIN"'),
 ("SEC-06", "security", "low", "Referrer-Policy header", 'Header always set Referrer-Policy "strict-origin-when-cross-origin"'),
 ("SEC-07", "security", "critical", "No sensitive files exposed (.env, .git, keys, configs)", "Delete or block these files from the web root immediately and rotate any secret in them."),
 ("SEC-08", "security", "high", "Repo security scan has no HIGH/CRITICAL findings", "Run scripts/ci_security_check.py and fix the cards it shows."),
 ("SEC-09", "security", "low", "Server software/version not leaked in headers", "Set ServerTokens Prod and remove X-Powered-By."),
 ("PERF-01", "performance", "high", "Server response time (TTFB) under 800 ms", "Add caching/CDN, check hosting plan, enable keep-alive."),
 ("PERF-02", "performance", "medium", "HTML document under 100 KB", "Move inline scripts/styles into cached files."),
 ("PERF-03", "performance", "medium", "Text compression (gzip/brotli) enabled", "Enable mod_deflate / brotli for html, js, css, json."),
 ("PERF-04", "performance", "medium", "Static assets cached (Cache-Control / Expires)", "Add long max-age for js, css, images, fonts."),
 ("PERF-05", "performance", "medium", "No image larger than 300 KB", "Convert to WebP/AVIF and resize."),
 ("PERF-06", "performance", "medium", "Main JS bundle under 3 MB", "Use --tree-shake-icons, deferred loading, avoid large packages."),
 ("SEO-01", "tech_seo", "high", "Title tag 10-60 characters", "Write a unique descriptive title, e.g. 'Trakr: QR Attendance Management Software'."),
 ("SEO-02", "tech_seo", "high", "Meta description 70-160 characters", "Write a 120-155 character summary with the main keyword."),
 ("SEO-03", "tech_seo", "medium", "Exactly one H1 heading", "Add one H1 describing the page."),
 ("SEO-04", "tech_seo", "medium", "<html lang> attribute set", 'Use <html lang="en">.'),
 ("SEO-05", "tech_seo", "medium", "Viewport meta tag present in served HTML", 'Add <meta name="viewport" content="width=device-width, initial-scale=1">.'),
 ("SEO-06", "tech_seo", "medium", "Canonical link present", 'Add <link rel="canonical" href="https://your-domain/">.'),
 ("SEO-07", "tech_seo", "critical", "Page is not blocked from indexing (noindex)", "Remove noindex from meta robots / X-Robots-Tag."),
 ("SEO-08", "tech_seo", "high", "robots.txt exists", "Add web/robots.txt with a Sitemap: line."),
 ("SEO-09", "tech_seo", "high", "sitemap.xml exists, valid and listed in robots.txt", "Generate sitemap.xml and reference it in robots.txt."),
 ("SEO-10", "tech_seo", "low", "Open Graph / Twitter card tags", "Add og:title, og:description, og:image, twitter:card."),
 ("SEO-11", "tech_seo", "critical", "Crawlable text in the served HTML (150+ words)", "Flutter web renders in canvas: add a static HTML landing page or prerender with real text."),
 ("SEO-12", "tech_seo", "medium", "Unknown URLs return a real 404 (not a soft 404)", "Return HTTP 404 for missing paths instead of the app shell with 200."),
 ("SEO-13", "tech_seo", "low", "Images have alt text", "Add alt to every <img>."),
 ("SEO-14", "tech_seo", "low", "Favicon and web manifest linked", "Add <link rel=icon> and <link rel=manifest>."),
 ("SEO-15", "tech_seo", "medium", "At least 3 crawlable internal links (<a href>)", "Add real anchor links to features, pricing, contact pages."),
 ("AI-01", "ai_search", "high", "AI search bots allowed in robots.txt (OAI-SearchBot, ChatGPT-User, Claude-SearchBot, Claude-User, PerplexityBot, Perplexity-User, Googlebot, bingbot)", "Remove Disallow rules for these bots so ChatGPT, Claude, Perplexity, Gemini and Copilot can cite you."),
 ("AI-02", "ai_search", "low", "Explicit AI training-bot policy in robots.txt (GPTBot, ClaudeBot, Google-Extended, CCBot, Applebot-Extended)", "Decide allow/disallow per bot and write it in robots.txt."),
 ("AI-03", "ai_search", "medium", "llms.txt present with title and links", "Add /llms.txt: H1, one-line summary, links to key pages."),
 ("AI-04", "ai_search", "high", "AI/search bots not blocked at server/WAF level", "Check firewall/WAF/hosting rules returning 403 to these user agents."),
 ("AI-05", "ai_search", "high", "Content readable without JavaScript (AI crawlers rarely run JS)", "Serve real text in HTML (static landing, prerender)."),
 ("AI-06", "ai_search", "medium", "Answer-ready content (3+ H2 sections or FAQ markup)", "Add FAQ / how-it-works sections written as questions and answers."),
 ("AI-07", "ai_search", "medium", "Entity clarity: Organization schema with sameAs links", "Add Organization JSON-LD with sameAs (LinkedIn, X, GitHub...)."),
 ("AI-08", "ai_search", "low", "Sitemap has lastmod dates (freshness signal)", "Add <lastmod> to each sitemap URL."),
 ("LOC-01", "local_seo", "medium", "Business phone number visible or in schema", "Show the phone in a tel: link and in schema."),
 ("LOC-02", "local_seo", "medium", "Business address visible or in schema", "Show the full postal address on the page."),
 ("LOC-03", "local_seo", "low", "City / service area named in content (use --city)", "Mention the city and service area in headings and text."),
 ("LOC-04", "local_seo", "medium", "LocalBusiness/Organization schema with address + telephone", "Add JSON-LD with address, telephone, openingHours, geo."),
 ("LOC-05", "local_seo", "low", "Google Maps / Business Profile link", "Link your Google Business Profile or Maps listing."),
 ("LOC-06", "local_seo", "low", "Contact or About page linked", "Add /contact and /about pages with NAP details."),
 ("SCH-01", "schema", "high", "JSON-LD structured data present in served HTML", "Add <script type=application/ld+json> blocks to the static HTML."),
 ("SCH-02", "schema", "high", "All JSON-LD blocks are valid JSON", "Fix the JSON syntax of the failing block."),
 ("SCH-03", "schema", "medium", '@context is https://schema.org', 'Use "@context": "https://schema.org".'),
 ("SCH-04", "schema", "medium", "Organization schema with name, url, logo", "Add Organization with name, url, logo, sameAs."),
 ("SCH-05", "schema", "low", "WebSite schema with name and url", "Add WebSite schema."),
 ("SCH-06", "schema", "medium", "SoftwareApplication schema (name, applicationCategory, operatingSystem, offers)", "Add SoftwareApplication schema describing Trakr."),
 ("SCH-07", "schema", "low", "FAQPage or BreadcrumbList schema", "Add FAQPage markup for visible Q&A."),
 ("WEB-01", "functional", "critical", "Home page returns HTTP 200", "Fix hosting/deploy: the home page must load."),
 ("WEB-02", "functional", "high", "Key files reachable (robots.txt, sitemap.xml, manifest.json, favicon)", "Deploy the missing files."),
 ("WEB-03", "functional", "medium", "Web manifest valid (name, icons, start_url, display)", "Complete manifest.json."),
 ("WEB-04", "functional", "medium", "No broken internal links on the home page", "Fix or remove the broken links."),
 ("WEB-05", "functional", "medium", "No mixed content (http:// resources on https page)", "Use https:// for every resource."),
 ("WEB-06", "functional", "medium", "No debug/test pages exposed (hosting_check.html, phpinfo.php ...)", "Remove them from the production build."),
 ("WEB-07", "functional", "medium", "Referenced scripts/styles/images load (HTTP 200)", "Fix paths of the failing assets."),
 ("WEB-08", "functional", "medium", "Custom paths return 200 (--paths)", "Fix the routes that fail."),
 ("TEST-01", "testing", "high", "At least 10 unit/widget test files", "Add tests for attendance, auth, QR and permissions."),
 ("TEST-02", "testing", "critical", "flutter test passes", "Fix failing tests."),
 ("TEST-03", "testing", "medium", "Critical areas covered (auth, attendance, qr, leave/payroll, permissions)", "Add tests for the uncovered areas."),
 ("TEST-04", "testing", "medium", "CI workflow runs the tests", "Add a flutter test step to your workflow."),
 ("TEST-05", "testing", "medium", "Integration / end-to-end tests exist", "Add integration_test/ for login, scan QR, mark attendance."),
 ("TEST-06", "testing", "low", "Cloud Functions have tests", "Add tests under functions/ (jest or the firebase emulator)."),
 ("BUG-01", "bugs", "critical", "flutter analyze reports no errors", "Fix every error line printed by flutter analyze."),
 ("BUG-02", "bugs", "medium", "No empty catch blocks swallowing errors", "Log or handle every exception."),
 ("BUG-03", "bugs", "low", "10 or fewer FIXME/HACK/XXX markers", "Resolve or ticket them."),
 ("BUG-04", "bugs", "low", "20 or fewer print() calls in lib/", "Replace with a logger / remove."),
]
META = {r[0]: r for r in RULES}
RESULTS = {}


def res(rid, status, detail=""):
    RESULTS[rid] = (status, detail)


# ------------------------------------------------------------------ fetching
class Resp:
    def __init__(self, status=0, headers=None, body=b"", wire=0, ttfb=0.0, total=0.0, err="", url=""):
        self.status, self.headers, self.body, self.wire = status, headers or {}, body, wire
        self.ttfb, self.total, self.err, self.url = ttfb, total, err, url

    @property
    def text(self):
        return self.body.decode("utf-8", "replace")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def http_get(url, ua=UA, follow=True, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": ua, "Accept-Encoding": "gzip", "Accept": "*/*"})
    opener = urllib.request.build_opener() if follow else urllib.request.build_opener(_NoRedirect)
    t0 = time.time()
    try:
        r = opener.open(req, timeout=timeout)
    except urllib.error.HTTPError as e:
        r = e
    except Exception as e:
        return Resp(err=str(e), url=url)
    ttfb = (time.time() - t0) * 1000
    try:
        raw = r.read()
    except Exception as e:
        return Resp(status=r.getcode() or 0, err=str(e), url=url)
    headers = {k.lower(): v for k, v in r.headers.items()}
    body = raw
    if headers.get("content-encoding") == "gzip":
        try:
            body = gzip.decompress(raw)
        except Exception:
            pass
    return Resp(r.getcode(), headers, body, len(raw), ttfb, (time.time() - t0) * 1000, "", getattr(r, "url", url))


class Site:
    def __init__(self, url, site_dir, repo):
        self.live, self.dir, self.repo = bool(url), site_dir, repo
        self.origin = url.rstrip("/") if url else "http://local.invalid"
        self.host = urllib.parse.urlparse(self.origin).netloc
        self._cache = {}

    def url(self, path):
        return urllib.parse.urljoin(self.origin + "/", path)

    def internal(self, absurl):
        return urllib.parse.urlparse(absurl).netloc == self.host

    def get(self, path_or_url, **kw):
        u = self.url(path_or_url)
        key = (u, tuple(sorted(kw.items())))
        if key in self._cache:
            return self._cache[key]
        if self.live:
            r = http_get(u, **kw)
        else:
            p = urllib.parse.urlparse(u).path or "/"
            p = urllib.parse.unquote(p)
            fp = os.path.join(self.dir, "index.html" if p == "/" else p.lstrip("/"))
            if os.path.isdir(fp):
                fp = os.path.join(fp, "index.html")
            if os.path.isfile(fp):
                b = open(fp, "rb").read()
                r = Resp(200, {"_local": "1"}, b, len(b), 0, 0, "", u)
            else:
                r = Resp(404, {"_local": "1"}, b"", 0, 0, 0, "", u)
        self._cache[key] = r
        return r

    def htaccess(self):
        for d in (self.dir, os.path.join(self.repo, "web")):
            p = os.path.join(d, ".htaccess")
            if os.path.isfile(p):
                return open(p, encoding="utf-8", errors="replace").read()
        return None


# ------------------------------------------------------------------- parsing
class Page(HTMLParser):
    SKIP = {"script", "style", "noscript", "template"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title, self.metas, self.links, self.h1, self.h2, self.anchors = "", [], [], 0, 0, []
        self.scripts, self.imgs, self.lang, self.words, self.ld = [], [], "", 0, []
        self._stack, self._buf, self._in_title = [], "", False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self._stack.append(tag)
        if tag == "html":
            self.lang = a.get("lang", "")
        elif tag == "title":
            self._in_title = True
        elif tag == "meta":
            self.metas.append(a)
        elif tag == "link":
            self.links.append(a)
        elif tag == "h1":
            self.h1 += 1
        elif tag == "h2":
            self.h2 += 1
        elif tag == "a" and a.get("href") is not None:
            self.anchors.append(a["href"])
        elif tag == "img":
            self.imgs.append(a)
        elif tag == "script":
            self.scripts.append(a)
            if a.get("type", "").lower() == "application/ld+json":
                self._buf = ""

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False
        if tag == "script" and self._stack and self._stack[-1] == "script":
            if self.scripts and self.scripts[-1].get("type", "").lower() == "application/ld+json":
                self.ld.append(self._buf)
        if tag in self._stack:
            while self._stack and self._stack.pop() != tag:
                pass

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        if self._stack and self._stack[-1] == "script":
            self._buf += data
        if not any(t in self.SKIP for t in self._stack) and not self._in_title:
            self.words += len([w for w in data.split() if re.search(r"[A-Za-z\u0900-\u0DFF]", w)])

    def meta(self, key, val="name"):
        for m in self.metas:
            if (m.get(val) or "").lower() == key.lower():
                return m.get("content", "")
        return None


def jsonld_items(blocks):
    items, errors = [], 0
    for b in blocks:
        try:
            d = json.loads(b)
        except Exception:
            errors += 1
            continue
        stack = d if isinstance(d, list) else [d]
        for x in stack:
            if isinstance(x, dict):
                if "@graph" in x and isinstance(x["@graph"], list):
                    items += [g for g in x["@graph"] if isinstance(g, dict)]
                items.append(x)
    return items, errors


def types_of(it):
    t = it.get("@type", [])
    return [t] if isinstance(t, str) else list(t)


def find(items, pred):
    return [i for i in items if any(pred(t) for t in types_of(i))]


def is_org(t):
    return t.endswith(("Organization", "Corporation", "Business", "Company", "Store", "Service"))


# -------------------------------------------------------------------- checks
def check_security(site):
    home = site.get("/")
    if site.live:
        h = home.headers
        http_url = "http://" + site.host + "/"
        if re.match(r"https?://(localhost|127\.0\.0\.1)", site.origin):
            res("SEC-01", "SKIP", "localhost")
        elif site.origin.startswith("https"):
            r = http_get(http_url, follow=False)
            loc = r.headers.get("location", "")
            if r.status in (301, 302, 307, 308) and loc.startswith("https://"):
                res("SEC-01", "PASS", f"{http_url} -> {loc}")
            else:
                res("SEC-01", "FAIL", f"http:// answered {r.status or r.err}, no redirect to https")
        else:
            res("SEC-01", "FAIL", "site URL is not https")
        csp = h.get("content-security-policy", "")
        res("SEC-02", "PASS" if "strict-transport-security" in h else "FAIL", h.get("strict-transport-security", "header missing"))
        res("SEC-03", "PASS" if csp else "FAIL", (csp[:80] + "...") if csp else "header missing")
        res("SEC-04", "PASS" if h.get("x-content-type-options", "").lower() == "nosniff" else "FAIL", "")
        res("SEC-05", "PASS" if ("x-frame-options" in h or "frame-ancestors" in csp) else "FAIL", "")
        res("SEC-06", "PASS" if "referrer-policy" in h else "FAIL", "")
        srv = h.get("server", "") + " " + h.get("x-powered-by", "")
        leak = re.search(r"\d+\.\d+", srv) or "x-powered-by" in h
        res("SEC-09", "WARN" if leak else "PASS", srv.strip() if leak else "no version in headers")
    else:
        ht = site.htaccess()
        if ht is None:
            for rid in ("SEC-01", "SEC-02", "SEC-03", "SEC-04", "SEC-05", "SEC-06"):
                res(rid, "SKIP", "no .htaccess and no --url: cannot see response headers")
        else:
            def hh(n):
                return bool(re.search(rf"Header\s+(always\s+)?(set|add)\s+{n}", ht, re.I))
            res("SEC-01", "PASS" if re.search(r"RewriteCond.*HTTPS.*(off|!on)", ht, re.I) else "FAIL", "from .htaccess")
            res("SEC-02", "PASS" if hh("Strict-Transport-Security") else "FAIL", "from .htaccess")
            res("SEC-03", "PASS" if hh("Content-Security-Policy") else "FAIL", "from .htaccess")
            res("SEC-04", "PASS" if hh("X-Content-Type-Options") else "FAIL", "from .htaccess")
            res("SEC-05", "PASS" if hh("X-Frame-Options") or "frame-ancestors" in ht else "FAIL", "from .htaccess")
            res("SEC-06", "PASS" if hh("Referrer-Policy") else "FAIL", "from .htaccess")
    bad = []
    for p in ("/.env", "/.git/config", "/.git/HEAD", "/firebase.json", "/pubspec.yaml", "/serviceAccountKey.json",
              "/key.properties", "/.htpasswd", "/functions/.env", "/backup.zip", "/database.rules.json"):
        r = site.get(p)
        if r.status == 200 and len(r.body) > 0 and b"<html" not in r.body[:300].lower():
            bad.append(p)
        elif r.status == 200 and site.live and p in ("/.env", "/.git/config") and b"[core]" in r.body:
            bad.append(p)
    res("SEC-07", "FAIL" if bad else "PASS", ("exposed: " + ", ".join(bad)) if bad else "none of 11 probed paths reachable")
    # repo scanner
    here = os.path.dirname(os.path.abspath(__file__))
    cands = [os.path.join(site.repo, "scripts", "ci_security_check.py"), os.path.join(here, "ci_security_check.py"),
             os.path.join(site.repo, "ci_security_check.py")]
    sc = next((c for c in cands if os.path.isfile(c)), None)
    if not sc:
        res("SEC-08", "SKIP", "ci_security_check.py not found (put it in scripts/)")
    else:
        tmp = tempfile.mkdtemp()
        subprocess.run([sys.executable, sc, "--root", site.repo, "--report-dir", tmp, "--only",
                        "secrets,firebase,android,functions,code,workflows"], capture_output=True, text=True)
        try:
            fs = json.load(open(os.path.join(tmp, "report.json")))["findings"]
            hi = [f for f in fs if f["sev"] in ("HIGH", "CRITICAL")]
            md = [f for f in fs if f["sev"] == "MEDIUM"]
            res("SEC-08", "FAIL" if hi else ("WARN" if md else "PASS"),
                f"{len(hi)} high/critical, {len(md)} medium. e.g. " + (hi[0]["msg"][:90] if hi else (md[0]["msg"][:90] if md else "clean")))
        except Exception as e:
            res("SEC-08", "SKIP", f"scanner produced no report ({e})")


def check_pages(site, args):
    home = site.get("/")
    pg = Page()
    if home.status == 200:
        try:
            pg.feed(home.text)
        except Exception:
            pass
    items, jerr = jsonld_items(pg.ld)
    html = home.text if home.status == 200 else ""
    # ---------------- performance
    if site.live:
        t = home.ttfb
        res("PERF-01", "PASS" if t < 800 else ("WARN" if t < 1800 else "FAIL"), f"{t:.0f} ms")
        enc = home.headers.get("content-encoding", "")
        res("PERF-03", "PASS" if enc in ("gzip", "br", "deflate") else "FAIL", enc or "uncompressed")
    else:
        res("PERF-01", "SKIP", "needs --url")
        ht = site.htaccess()
        if ht:
            res("PERF-03", "PASS" if re.search(r"mod_deflate|AddOutputFilterByType\s+DEFLATE|mod_brotli", ht, re.I) else "FAIL", "from .htaccess")
        else:
            res("PERF-03", "SKIP", "needs --url or .htaccess")
    kb = len(home.body) / 1024
    res("PERF-02", ("PASS" if kb <= 100 else ("WARN" if kb <= 300 else "FAIL")) if home.status == 200 else "SKIP", f"{kb:.1f} KB")
    # referenced resources
    refs = []
    for s in pg.scripts:
        if s.get("src"):
            refs.append(s["src"])
    for l in pg.links:
        if l.get("href") and (l.get("rel", "") or "").lower().split()[0:1] in (["stylesheet"], ["icon"], ["manifest"], ["apple-touch-icon"]):
            refs.append(l["href"])
    refs += [i["src"] for i in pg.imgs if i.get("src") and not i["src"].startswith("data:")]
    refs += ["/main.dart.js", "/flutter_bootstrap.js"]
    seen, fetched = set(), []
    for r in refs:
        u = site.url(r)
        if u in seen or not site.internal(u) or len(seen) >= 25:
            continue
        seen.add(u)
        fetched.append((r, site.get(u)))
    if site.live:
        stat = [(r, x) for r, x in fetched if x.status == 200 and re.search(r"\.(js|css|png|jpe?g|webp|svg|woff2?|ico)(\?|$)", r)]
        if stat:
            ok = [r for r, x in stat if re.search(r"max-age=(\d+)", x.headers.get("cache-control", "")) and
                  int(re.search(r"max-age=(\d+)", x.headers.get("cache-control", "")).group(1)) >= 86400 or "expires" in x.headers]
            ratio = len(ok) / len(stat)
            res("PERF-04", "PASS" if ratio >= .7 else ("WARN" if ratio >= .3 else "FAIL"), f"{len(ok)}/{len(stat)} assets cached 1 day+")
        else:
            res("PERF-04", "SKIP", "no static assets found")
    else:
        ht = site.htaccess()
        res("PERF-04", ("PASS" if re.search(r"mod_expires|ExpiresActive|Cache-Control", ht, re.I) else "FAIL") if ht else "SKIP",
            "from .htaccess" if ht else "needs --url or .htaccess")
    imgs = []
    for dp, dn, fn in os.walk(site.dir):
        for f in fn:
            if f.lower().endswith((".png", ".jpg", ".jpeg", ".webp", ".gif")):
                imgs.append((os.path.getsize(os.path.join(dp, f)), os.path.relpath(os.path.join(dp, f), site.dir)))
    for r, x in fetched:
        if x.status == 200 and re.search(r"\.(png|jpe?g|webp|gif)(\?|$)", r):
            imgs.append((x.wire, r))
    if imgs:
        sz, nm = max(imgs)
        res("PERF-05", "PASS" if sz <= 300_000 else ("WARN" if sz <= 800_000 else "FAIL"), f"largest {nm}: {sz // 1024} KB")
    else:
        res("PERF-05", "SKIP", "no images found")
    bundle = None
    for cand in (os.path.join(site.dir, "main.dart.js"),):
        if os.path.isfile(cand):
            bundle = os.path.getsize(cand)
    if bundle is None:
        for r, x in fetched:
            if r.endswith("main.dart.js") and x.status == 200:
                bundle = len(x.body)
    if bundle is None:
        res("PERF-06", "SKIP", "main.dart.js not found (build the web app: flutter build web --release)")
    else:
        res("PERF-06", "PASS" if bundle <= 3_000_000 else ("WARN" if bundle <= 6_000_000 else "FAIL"), f"{bundle / 1e6:.1f} MB")

    # ---------------- tech SEO
    if home.status != 200:
        for rid in [r[0] for r in RULES if r[1] in ("tech_seo", "schema", "local_seo")] + ["AI-05", "AI-06", "AI-07"]:
            if rid not in ("SEO-08", "SEO-09", "SEO-12"):
                res(rid, "SKIP", "home page did not load")
    else:
        t = pg.title.strip()
        res("SEO-01", "PASS" if 10 <= len(t) <= 60 else "FAIL", f'"{t}" ({len(t)} chars)')
        d = (pg.meta("description") or "").strip()
        res("SEO-02", "PASS" if 70 <= len(d) <= 160 else ("WARN" if d else "FAIL"), f"{len(d)} chars" if d else "missing")
        res("SEO-03", "PASS" if pg.h1 == 1 else "FAIL", f"{pg.h1} H1 tag(s) in served HTML")
        res("SEO-04", "PASS" if pg.lang else "FAIL", pg.lang or "missing")
        res("SEO-05", "PASS" if pg.meta("viewport") else "WARN", "present" if pg.meta("viewport") else "not in static HTML (Flutter adds it at runtime)")
        can = [l for l in pg.links if (l.get("rel") or "").lower() == "canonical"]
        res("SEO-06", "PASS" if can else "FAIL", can[0].get("href", "") if can else "missing")
        rob = (pg.meta("robots") or "").lower() + " " + home.headers.get("x-robots-tag", "").lower()
        res("SEO-07", "FAIL" if "noindex" in rob else "PASS", rob.strip() or "no robots meta")
        og = [m for m in pg.metas if (m.get("property") or "").startswith("og:")]
        tw = pg.meta("twitter:card")
        res("SEO-10", "PASS" if len(og) >= 3 and tw else ("WARN" if og or tw else "FAIL"), f"{len(og)} og tags, twitter:card={'yes' if tw else 'no'}")
        words = pg.words
        spa = "flutter" in html.lower() and words < 100
        res("SEO-11", "PASS" if words >= 150 else ("WARN" if words >= 50 else "FAIL"),
            f"{words} words" + (" (client-side Flutter app: crawlers see an empty page)" if spa else ""))
        res("AI-05", "PASS" if words >= 150 else ("WARN" if words >= 50 else "FAIL"), f"{words} words without JavaScript")
        noalt = [i for i in pg.imgs if not (i.get("alt") or "").strip()]
        res("SEO-13", "SKIP" if not pg.imgs else ("PASS" if not noalt else "WARN"), f"{len(noalt)}/{len(pg.imgs)} images without alt")
        icon = any("icon" in (l.get("rel") or "") for l in pg.links)
        man = any((l.get("rel") or "") == "manifest" for l in pg.links)
        res("SEO-14", "PASS" if icon and man else ("WARN" if icon or man else "FAIL"), f"icon={icon} manifest={man}")
        hrefs = [a for a in pg.anchors if a and not a.startswith(("#", "javascript:", "mailto:", "tel:"))]
        res("SEO-15", "PASS" if len(hrefs) >= 3 else ("WARN" if hrefs else "FAIL"), f"{len(hrefs)} anchor links")
        res("AI-06", "PASS" if (pg.h2 >= 3 or find(items, lambda t: t == "FAQPage")) else "FAIL",
            f"{pg.h2} H2 headings, FAQ schema={'yes' if find(items, lambda t: t == 'FAQPage') else 'no'}")
        # ---------------- schema
        res("SCH-01", "PASS" if items else "FAIL", f"{len(items)} schema item(s)" if items else "no JSON-LD in served HTML")
        if not items and not jerr:
            for rid in ("SCH-02", "SCH-03"):
                res(rid, "SKIP", "no JSON-LD")
        else:
            res("SCH-02", "FAIL" if jerr else "PASS", f"{jerr} invalid block(s)" if jerr else "all valid")
            ctx = [b for b in pg.ld if "schema.org" in b]
            res("SCH-03", "PASS" if ctx and len(ctx) == len(pg.ld) else "FAIL", "")
        orgs = find(items, is_org)
        def has(it, *ks):
            return all(it.get(k) for k in ks)
        okorg = [o for o in orgs if has(o, "name", "url", "logo")]
        res("SCH-04", "PASS" if okorg else ("WARN" if orgs else "FAIL"), "Organization complete" if okorg else ("Organization missing name/url/logo" if orgs else "no Organization"))
        res("SCH-05", "PASS" if [w for w in find(items, lambda t: t == "WebSite") if has(w, "name", "url")] else "FAIL", "")
        sa = [s for s in find(items, lambda t: t in ("SoftwareApplication", "WebApplication", "MobileApplication")) if has(s, "name", "applicationCategory", "operatingSystem")]
        res("SCH-06", "PASS" if sa else "FAIL", "")
        res("SCH-07", "PASS" if find(items, lambda t: t in ("FAQPage", "BreadcrumbList")) else "WARN", "")
        sameas = any(o.get("sameAs") for o in orgs)
        res("AI-07", "PASS" if okorg and sameas else ("WARN" if orgs else "FAIL"), f"Organization={'yes' if orgs else 'no'} sameAs={'yes' if sameas else 'no'}")
        # ---------------- local SEO
        blob = html + json.dumps(items)
        phone = re.search(r"tel:|\"telephone\"|\+\d{1,3}[\s-]?\d[\d\s-]{7,}|\b\d{5}[\s-]?\d{5}\b", blob)
        res("LOC-01", "PASS" if phone else "FAIL", "")
        addr = re.search(r"\"address\"|streetAddress|\b\d{6}\b|\b(?:Street|Road|Nagar|Floor|Avenue)\b", blob)
        res("LOC-02", "PASS" if addr else "FAIL", "")
        if args.city:
            res("LOC-03", "PASS" if args.city.lower() in blob.lower() else "FAIL", f"'{args.city}' {'found' if args.city.lower() in blob.lower() else 'not found'} in page")
        else:
            res("LOC-03", "SKIP", "pass --city <name> to check")
        lb = [o for o in orgs if o.get("address") and o.get("telephone")]
        res("LOC-04", "PASS" if lb else ("WARN" if orgs else "FAIL"), "")
        res("LOC-05", "PASS" if re.search(r"google\.[a-z.]+/maps|maps\.app\.goo\.gl|g\.page|goo\.gl/maps", blob) else "FAIL", "")
        res("LOC-06", "PASS" if any(re.search(r"contact|about", a, re.I) for a in pg.anchors) else "FAIL", "")

    # ---------------- AI-08 / SEO-08/09 / AI-02/03
    rb = site.get("/robots.txt")
    res("SEO-08", "PASS" if rb.status == 200 and b"<html" not in rb.body[:200].lower() else "FAIL", "found" if rb.status == 200 else f"HTTP {rb.status}")
    rtxt = rb.text if rb.status == 200 and b"<html" not in rb.body[:200].lower() else ""
    sm = site.get("/sitemap.xml")
    smurls, lastmods, valid = [], 0, False
    if sm.status == 200:
        try:
            root = ET.fromstring(sm.body)
            valid = True
            for e in root.iter():
                if e.tag.endswith("}loc") or e.tag == "loc":
                    smurls.append((e.text or "").strip())
                if e.tag.endswith("}lastmod") or e.tag == "lastmod":
                    lastmods += 1
        except Exception:
            pass
    listed = "sitemap:" in rtxt.lower()
    if valid and smurls:
        res("SEO-09", "PASS" if listed else "WARN", f"{len(smurls)} URLs" + ("" if listed else ", but robots.txt has no Sitemap: line"))
    else:
        res("SEO-09", "FAIL", "sitemap.xml missing or invalid")
    res("AI-08", ("PASS" if lastmods >= len(smurls) else "WARN") if smurls else "SKIP", f"{lastmods}/{len(smurls)} URLs have lastmod")
    if rtxt:
        rp = urllib.robotparser.RobotFileParser()
        rp.parse(rtxt.splitlines())
        search_bots = ["OAI-SearchBot", "ChatGPT-User", "Claude-SearchBot", "Claude-User", "PerplexityBot", "Perplexity-User", "Googlebot", "bingbot"]
        blocked = [b for b in search_bots if not rp.can_fetch(b, "/")]
        res("AI-01", "FAIL" if blocked else "PASS", ("blocked: " + ", ".join(blocked)) if blocked else "all 8 search/answer bots allowed")
        train = ["GPTBot", "ClaudeBot", "Google-Extended", "CCBot", "Applebot-Extended"]
        named = [b for b in train if re.search(rf"user-agent:\s*{re.escape(b)}", rtxt, re.I)]
        res("AI-02", "PASS" if named else "WARN", ("explicit rules for " + ", ".join(named)) if named else "no explicit policy (defaults apply)")
    else:
        res("AI-01", "WARN", "no robots.txt: bots allowed by default")
        res("AI-02", "WARN", "no robots.txt")
    ll = site.get("/llms.txt")
    if ll.status == 200 and b"<html" not in ll.body[:200].lower():
        t = ll.text
        ok = t.lstrip().startswith("#") and len(re.findall(r"\]\(https?://", t)) >= 2
        res("AI-03", "PASS" if ok else "WARN", "found" if ok else "found, but needs a '# Title' line and 2+ markdown links")
    else:
        res("AI-03", "FAIL", f"HTTP {ll.status}" if ll.status else "unreachable")
    if site.live:
        bad = []
        for bot in ("GPTBot", "ClaudeBot", "PerplexityBot", "Googlebot", "bingbot"):
            r = http_get(site.url("/"), ua=f"Mozilla/5.0 (compatible; {bot}/1.0)")
            if r.status in (401, 403, 429, 503) or r.status == 0:
                bad.append(f"{bot}:{r.status or 'err'}")
        res("AI-04", "FAIL" if bad else "PASS", ("blocked " + ", ".join(bad)) if bad else "5 bot user-agents got normal responses")
    else:
        res("AI-04", "SKIP", "needs --url")
    if site.live:
        r404 = site.get("/this-page-should-not-exist-trakr-9f3a")
        res("SEO-12", "PASS" if r404.status == 404 else "FAIL", f"HTTP {r404.status}")
    else:
        res("SEO-12", "SKIP", "needs --url")

    # ---------------- functional
    res("WEB-01", "PASS" if home.status == 200 else "FAIL", f"HTTP {home.status or home.err}")
    miss = [p for p in ("/robots.txt", "/sitemap.xml", "/manifest.json", "/favicon.png") if site.get(p).status != 200]
    if "/favicon.png" in miss and site.get("/favicon.ico").status == 200:
        miss.remove("/favicon.png")
    res("WEB-02", "PASS" if not miss else ("WARN" if len(miss) == 1 else "FAIL"), ("missing: " + ", ".join(miss)) if miss else "all reachable")
    m = site.get("/manifest.json")
    try:
        mj = json.loads(m.text)
        need = [k for k in ("name", "icons", "start_url", "display") if not mj.get(k)]
        res("WEB-03", "PASS" if not need else "WARN", ("missing " + ", ".join(need)) if need else "valid")
    except Exception:
        res("WEB-03", "FAIL" if m.status != 200 else "FAIL", "manifest.json missing or not valid JSON")
    if home.status == 200:
        internal = []
        for a in pg.anchors:
            if a.startswith(("#", "javascript:", "mailto:", "tel:")):
                continue
            u = site.url(a)
            if site.internal(u) and u.split("#")[0] not in internal:
                internal.append(u.split("#")[0])
        broken = [u for u in internal[:30] if site.get(u).status >= 400 or site.get(u).status == 0]
        res("WEB-04", "SKIP" if not internal else ("PASS" if not broken else "FAIL"), f"{len(broken)} broken of {len(internal[:30])} checked" + (": " + ", ".join(broken[:3]) if broken else ""))
        mixed = re.findall(r"""(?:src|href)=["']http://(?!localhost|www\.w3\.org)[^"']+""", html)
        res("WEB-05", "SKIP" if not site.origin.startswith("https") else ("FAIL" if mixed else "PASS"), f"{len(mixed)} http:// resource(s)" if mixed else "none")
        failed = [r for r, x in fetched if x.status >= 400 or x.status == 0]
        failed = [r for r in failed if not r.endswith(("main.dart.js", "flutter_bootstrap.js")) or r in [s.get("src") for s in pg.scripts]]
        res("WEB-07", "PASS" if not failed else "FAIL", f"{len(failed)} failing: " + ", ".join(failed[:3]) if failed else f"{len(fetched)} assets ok")
    else:
        for rid in ("WEB-04", "WEB-05", "WEB-07"):
            res(rid, "SKIP", "home page did not load")
    dbg = [p for p in ("/hosting_check.html", "/test.html", "/debug.html", "/phpinfo.php", "/info.php", "/test.php") if site.get(p).status == 200]
    res("WEB-06", "FAIL" if dbg else "PASS", ("exposed: " + ", ".join(dbg)) if dbg else "none found")
    if args.paths:
        bad = [p for p in args.paths if site.get(p).status != 200]
        res("WEB-08", "PASS" if not bad else "FAIL", ("failing: " + ", ".join(bad)) if bad else f"{len(args.paths)} path(s) ok")
    else:
        res("WEB-08", "SKIP", "no --paths given")


def run(cmd, cwd, timeout=1200):
    try:
        c = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return c.returncode, (c.stdout or "") + (c.stderr or "")
    except Exception as e:
        return 127, str(e)


def check_repo(site, args):
    repo = site.repo
    tests = [p for p in glob.glob(os.path.join(repo, "test", "**", "*_test.dart"), recursive=True)]
    n = len(tests)
    res("TEST-01", "PASS" if n >= 10 else ("WARN" if n >= 3 else "FAIL"), f"{n} test file(s)")
    names = " ".join(os.path.relpath(t, repo).lower() for t in tests)
    areas = {"auth": ["auth", "login"], "attendance": ["attendance", "checkin", "check_in"], "qr": ["qr"],
             "leave/payroll": ["leave", "payroll", "salary"], "permissions": ["permission", "role", "rbac"]}
    missing = [a for a, ks in areas.items() if not any(k in names for k in ks)]
    res("TEST-03", "PASS" if not missing else ("WARN" if len(missing) <= 2 else "FAIL"), ("no tests for: " + ", ".join(missing)) if missing else "all areas covered")
    wf = " ".join(open(p, encoding="utf-8", errors="replace").read() for p in glob.glob(os.path.join(repo, ".github", "workflows", "*.y*ml")))
    res("TEST-04", "PASS" if re.search(r"flutter test|npm (run )?test|jest|pytest", wf) else "FAIL", "")
    it = os.path.isdir(os.path.join(repo, "integration_test")) or os.path.isdir(os.path.join(repo, "e2e"))
    res("TEST-05", "PASS" if it else "FAIL", "integration_test/ found" if it else "no integration_test/ folder")
    ft = glob.glob(os.path.join(repo, "functions", "**", "*.test.*"), recursive=True) + glob.glob(os.path.join(repo, "functions", "test", "**", "*"), recursive=True)
    ft = [f for f in ft if "node_modules" not in f and os.path.isfile(f)]
    res("TEST-06", "PASS" if ft else ("SKIP" if not os.path.isdir(os.path.join(repo, "functions")) else "FAIL"), f"{len(ft)} file(s)")
    # static bug scans
    empty, todo, prints = [], 0, 0
    for p in glob.glob(os.path.join(repo, "lib", "**", "*.dart"), recursive=True) + glob.glob(os.path.join(repo, "functions", "src", "**", "*.ts"), recursive=True):
        t = open(p, encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"catch\s*\([^)]*\)\s*\{\s*\}", t):
            empty.append(f"{os.path.relpath(p, repo)}:{t[:m.start()].count(chr(10)) + 1}")
        todo += len(re.findall(r"\b(FIXME|HACK|XXX)\b", t))
        if p.endswith(".dart"):
            prints += len(re.findall(r"^\s*print\(", t, re.M))
    res("BUG-02", "PASS" if not empty else ("WARN" if len(empty) <= 3 else "FAIL"), f"{len(empty)} empty catch" + (": " + ", ".join(empty[:3]) if empty else ""))
    res("BUG-03", "PASS" if todo <= 10 else "WARN", f"{todo} marker(s)")
    res("BUG-04", "PASS" if prints <= 20 else "WARN", f"{prints} print() call(s)")
    if args.skip_exec or not shutil.which("flutter"):
        why = "--skip-exec" if args.skip_exec else "flutter not installed"
        res("TEST-02", "SKIP", why)
        res("BUG-01", "SKIP", why)
    else:
        code, out = run(["flutter", "analyze", "--no-pub"], repo)
        errs = [l for l in out.splitlines() if re.match(r"\s*error\s", l)]
        res("BUG-01", "PASS" if not errs else "FAIL", f"{len(errs)} error(s)" + (": " + errs[0].strip()[:90] if errs else ""))
        code, out = run(["flutter", "test"], repo)
        last = (out.strip().splitlines() or [""])[-1][:90]
        res("TEST-02", "PASS" if code == 0 else "FAIL", last)


# ------------------------------------------------------------------- scoring
def score():
    cat_scores = {}
    for c in CATS:
        got = tot = 0.0
        n = 0
        for rid, (st, _) in RESULTS.items():
            m = META[rid]
            if m[1] != c or st == "SKIP":
                continue
            w = SEV_W[m[2]]
            tot += w
            got += w * CREDIT[st]
            n += 1
        cat_scores[c] = round(100 * got / tot) if tot else None
    def blend(mix):
        num = den = 0
        for c, w in mix.items():
            if cat_scores.get(c) is not None:
                num += w * cat_scores[c]
                den += w
        return round(num / den) if den else None
    overall = blend({c: w for c, (_, w) in CATS.items()})
    return cat_scores, overall, blend(GOOGLE_SEO_MIX)


def grade(s):
    return "-" if s is None else "A" if s >= 90 else "B" if s >= 80 else "C" if s >= 70 else "D" if s >= 60 else "F"


# -------------------------------------------------------------------- output
def terminal(cs, overall, gseo, args, mode):
    import textwrap
    color = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
    R, Y, G, D, B, C = "31", "33", "32", "2", "1", "36"
    c = lambda t, code: f"\033[{code}m{t}\033[0m" if color else t
    col = lambda v: D if v is None else (G if v >= 80 else (Y if v >= 60 else R))
    show = lambda v: "--" if v is None else str(v)
    out = ["", c("  Trakr Quality Audit", f"{B};{C}"),
           c(f"  {datetime.now().strftime('%Y-%m-%d')}  |  mode: {mode}  |  {sum(1 for v in RESULTS.values() if v[0] != 'SKIP')} rules evaluated, "
             f"{sum(1 for v in RESULTS.values() if v[0] == 'SKIP')} skipped", D), ""]
    out.append("  " + "\u256d" + "\u2500" * 70 + "\u256e")
    line = f"  OVERALL {show(overall)}/100 ({grade(overall)})     GOOGLE SEO {show(gseo)}/100     AI SEARCH {show(cs['ai_search'])}/100"
    out.append("  \u2502" + line.ljust(70) + "\u2502")
    out.append("  " + "\u2570" + "\u2500" * 70 + "\u256f")
    if color:
        out[-2] = out[-2].replace(f"OVERALL {show(overall)}", c(f"OVERALL {show(overall)}", f"{B};{col(overall)}"))
    out.append("")
    keys = list(CATS)
    tw = 17
    for i in range(0, len(keys), 4):
        row = keys[i:i + 4]
        ls = ["", "", "", "", ""]
        for k in row:
            v = cs[k]
            fails = sum(1 for rid, (st, _) in RESULTS.items() if META[rid][1] == k and st == "FAIL")
            warns = sum(1 for rid, (st, _) in RESULTS.items() if META[rid][1] == k and st == "WARN")
            title = TILE[k]
            ls[0] += "  \u256d" + "\u2500" * tw + "\u256e"
            ls[1] += "  \u2502" + title.center(tw) + "\u2502"
            ls[2] += "  \u2502" + c(show(v).center(tw), f"{B};{col(v)}") + "\u2502"
            ls[3] += "  \u2502" + (f"{fails} fail {warns} warn" if v is not None else "skipped").center(tw) + "\u2502"
            ls[4] += "  \u2570" + "\u2500" * tw + "\u256f"
        out += ls
    out.append("")
    crit = [(rid, d) for rid, (st, d) in RESULTS.items() if st == "FAIL" and META[rid][2] in ("critical", "high")]
    crit.sort(key=lambda x: (SEV_W[META[x[0]][2]] * -1, x[0]))
    width = 96
    out.append(c("  \u25cf Critical & high failures", f"{B};{R}") + c("   FIX THIS WEEK", R) if crit else c("  \u25cf No critical or high failures", f"{B};{G}"))
    for rid, d in crit:
        m = META[rid]
        out.append("  \u250c" + "\u2500" * (width - 4) + "\u2510")
        for j, l in enumerate(textwrap.wrap(f"{rid}  {m[3]}", width - 16) or [""]):
            tag = c(f" {m[2].upper()} ", f"{B};{R}") if j == 0 else " " * (len(m[2]) + 2)
            out.append("  \u2502 " + tag + " " + l.ljust(width - 8 - len(m[2]) - 2) + " \u2502")
        if d:
            for l in textwrap.wrap("Found: " + d, width - 8):
                out.append("  \u2502 " + c(l.ljust(width - 6), D) + " \u2502")
        for l in textwrap.wrap("Fix: " + m[4], width - 8):
            out.append("  \u2502 " + l.ljust(width - 6) + " \u2502")
        out.append("  \u2514" + "\u2500" * (width - 4) + "\u2518")
    med = [(rid, d) for rid, (st, d) in RESULTS.items() if st in ("FAIL", "WARN") and (META[rid][2] in ("medium", "low") or st == "WARN")]
    med = [x for x in med if x not in crit]
    if med:
        out.append("")
        out.append(c(f"  \u25cf Other items to improve ({len(med)})", f"{B};{Y}"))
        for rid, d in sorted(med):
            st = RESULTS[rid][0]
            out.append(f"   {c(st, Y if st == 'WARN' else R)}  {rid:8} {META[rid][3][:62]}" + (c(f"  [{d[:40]}]", D) if d else ""))
    gate_fail = overall is not None and overall < args.fail_under or any(META[r][2] == "critical" and s == "FAIL" for r, (s, _) in RESULTS.items())
    out += ["", "  " + (c(f" RESULT: FAILED ", f"{B};41;37") + f"  score {show(overall)} (needs {args.fail_under}) or a critical rule failed" if gate_fail
                       else c(" RESULT: PASSED ", f"{B};42;30") + f"  score {show(overall)}"), ""]
    return "\n".join(out), gate_fail


def write_reports(d, cs, overall, gseo, mode):
    os.makedirs(d, exist_ok=True)
    rows = [{"id": r[0], "category": r[1], "severity": r[2], "title": r[3], "fix": r[4],
             "status": RESULTS.get(r[0], ("SKIP", "not evaluated"))[0], "detail": RESULTS.get(r[0], ("SKIP", ""))[1]} for r in RULES]
    json.dump({"generated": datetime.now().isoformat(), "mode": mode, "overall": overall, "google_seo": gseo,
               "categories": cs, "rules": rows}, open(os.path.join(d, "quality-report.json"), "w"), indent=1)
    color = {"PASS": "#1a7f37", "WARN": "#b7791f", "FAIL": "#cf222e", "SKIP": "#6e7781"}
    tiles = "".join(f'<div class="card"><div class="t">{H.escape(CATS[k][0])}</div><div class="s" style="color:{"#6e7781" if v is None else "#1a7f37" if v>=80 else "#b7791f" if v>=60 else "#cf222e"}">{"--" if v is None else v}</div></div>' for k, v in cs.items())
    trs = "".join(f'<tr><td><b style="color:{color[r["status"]]}">{r["status"]}</b></td><td>{r["id"]}</td><td>{r["severity"]}</td><td>{H.escape(r["title"])}</td><td>{H.escape(r["detail"])}</td><td>{H.escape(r["fix"]) if r["status"] in ("FAIL","WARN") else ""}</td></tr>' for r in rows)
    open(os.path.join(d, "quality-report.html"), "w", encoding="utf-8").write(f"""<!doctype html><meta charset=utf-8><title>Trakr quality report</title>
<style>body{{font-family:system-ui,sans-serif;background:#f6f8fa;color:#1f2328;margin:0}}.w{{max-width:1150px;margin:auto;padding:24px}}
.b{{background:#0969da;color:#fff;border-radius:10px;padding:18px 24px;font-size:22px;font-weight:700}}.g{{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:12px;margin:16px 0}}
.card{{background:#fff;border-radius:8px;padding:12px;box-shadow:0 1px 3px #0002}}.t{{font-size:13px;color:#57606a}}.s{{font-size:30px;font-weight:800}}
table{{width:100%;border-collapse:collapse;background:#fff;font-size:13px}}th,td{{text-align:left;padding:7px 9px;border-bottom:1px solid #eaeef2;vertical-align:top}}th{{background:#eaeef2}}</style>
<div class=w><div class=b>Overall {overall}/100 ({grade(overall)}) &middot; Google SEO {gseo}/100 &middot; AI search {cs['ai_search']}/100
<div style="font-size:13px;font-weight:400">mode: {mode} &middot; {datetime.now():%d %b %Y %H:%M}</div></div><div class=g>{tiles}</div>
<table><tr><th>Status</th><th>Rule</th><th>Severity</th><th>Check</th><th>Found</th><th>How to fix</th></tr>{trs}</table></div>""")


def list_rules(md):
    if not md:
        for r in RULES:
            print(f"{r[0]:8} {r[2]:9} {r[1]:12} {r[3]}")
        return
    print("# Trakr quality rules\n")
    print("Scoring: PASS = 100%, WARN = 50%, FAIL = 0% of the rule's weight (critical 5, high 3, medium 2, low 1). Skipped rules are ignored.")
    print("Overall score = weighted average of the category scores. Gate fails if overall < `--fail-under` (default 60) or any CRITICAL rule fails.\n")
    print("| Category | Weight |\n|---|---|")
    for k, (t, w) in CATS.items():
        print(f"| {t} | {w} |")
    print("\nGoogle SEO score = " + ", ".join(f"{CATS[k][0]} {w}%" for k, w in GOOGLE_SEO_MIX.items()) + ".\n")
    for k, (t, _) in CATS.items():
        print(f"## {t}\n\n| ID | Severity | Rule | How to fix |\n|---|---|---|---|")
        for r in RULES:
            if r[1] == k:
                print(f"| {r[0]} | {r[2]} | {r[3]} | {r[4]} |")
        print()


def main():
    ap = argparse.ArgumentParser(description="Trakr quality gate")
    ap.add_argument("--url", default="", help="live site, e.g. https://trakr.example.com")
    ap.add_argument("--repo", default=".", help="project root")
    ap.add_argument("--site-dir", default="", help="built web folder (default: build/web, else web)")
    ap.add_argument("--city", default="", help="city / service area expected in content")
    ap.add_argument("--paths", nargs="*", default=[], help="extra paths that must return 200, e.g. /login")
    ap.add_argument("--only", default="", help="categories: " + ",".join(CATS))
    ap.add_argument("--fail-under", type=int, default=60)
    ap.add_argument("--skip-exec", action="store_true", help="do not run flutter analyze/test")
    ap.add_argument("--report-dir", default="quality-reports")
    ap.add_argument("--list-rules", action="store_true")
    ap.add_argument("--md", action="store_true", help="with --list-rules: markdown output")
    a = ap.parse_args()
    if a.list_rules:
        return list_rules(a.md) or 0
    repo = os.path.abspath(a.repo)
    sd = a.site_dir or next((p for p in (os.path.join(repo, "build", "web"), os.path.join(repo, "web")) if os.path.isdir(p)), repo)
    site = Site(a.url, os.path.abspath(sd), repo)
    only = [x for x in a.only.split(",") if x]
    bad = [x for x in only if x not in CATS]
    if bad:
        ap.error(f"unknown categories {bad}")
    print(f"> {'LIVE ' + a.url if site.live else 'STATIC ' + os.path.relpath(site.dir, repo)} ...", flush=True)
    if site.live:
        probe = site.get("/")
        if probe.status == 0:
            print(f"Cannot reach {a.url}: {probe.err}", file=sys.stderr)
            return 2
    check_security(site)
    check_pages(site, a)
    check_repo(site, a)
    if only:
        for rid in list(RESULTS):
            if META[rid][1] not in only:
                del RESULTS[rid]
    cs, overall, gseo = score()
    if only:
        cs = {k: v for k, v in cs.items()}
    mode = "LIVE" if site.live else "STATIC"
    text, fail = terminal(cs, overall, gseo, a, mode)
    print(text)
    write_reports(a.report_dir, cs, overall, gseo, mode)
    print(f"  Reports: {a.report_dir}/quality-report.html, quality-report.json\n")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
