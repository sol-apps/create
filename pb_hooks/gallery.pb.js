/// <reference path="../pb_data/types.d.ts" />
/*
 * GET /api/gallery -> [{slug,title,description,emoji,url,repo,readme}]
 *
 * Server-side discovery for the gallery: proxies the GitHub org search
 * (org:sol-apps topic:solhann-app) plus each repo's README so visitors
 * never spend GitHub's anonymous 60/hr rate limit themselves.
 *
 * The rendered JSON is cached in-process (two primitive keys in
 * $app.store() — plain strings/numbers survive the goja VM pool, richer
 * objects don't round-trip reliably). On upstream failure the stale
 * cache is served instead of an error.
 *
 * GitHub's anonymous limit is shared by everything on this server; with
 * the 15-min TTL a refresh costs 1 search + N readme calls, ~4x/hr.
 * If that ever gets tight, set a runtime token from dev:
 *   pb-secret set create.GITHUB_TOKEN && pb-provision create --push-env
 */
routerAdd("GET", "/api/gallery", (e) => {
  const ORG = "sol-apps";
  const TOPIC = "solhann-app";
  const TTL_MS = 15 * 60 * 1000;
  const store = $app.store();

  // Unlisted apps: stripped from the public payload, included only when the
  // caller presents the passkey (?key=). Compared by sha256 so the plaintext
  // never lives in this public repo.
  const HIDDEN = ["architecture", "desk"];
  const KEY_HASH = "e7749c35f442f154e3a644e88a23a608f22f0d22afdf548f3f010afc34e3f7ad";
  const key = e.request.url.query().get("key") || "";
  const unlocked = key !== "" && $security.sha256(key) === KEY_HASH;
  const expose = (apps) => (unlocked ? apps : apps.filter((a) => HIDDEN.indexOf(a.slug) === -1));

  // versioned keys: bumping them abandons any stale cache surviving a JSVM
  // reload in the Go-side store ($app.store() outlives hook redeploys)
  const cachedAt = store.get("gallery_t_v2");
  const cachedJSON = store.get("gallery_json_v2");
  const fresh = cachedJSON && cachedAt && Date.now() - cachedAt < TTL_MS;
  if (fresh) {
    return e.json(200, expose(JSON.parse(cachedJSON)));
  }

  const gh = (url, accept) => {
    const headers = {
      "Accept": accept,
      "User-Agent": "solhann-gallery",
      "X-GitHub-Api-Version": "2022-11-28",
    };
    const token = $os.getenv("GITHUB_TOKEN");
    if (token) headers["Authorization"] = "Bearer " + token;
    return $http.send({ url: url, method: "GET", headers: headers, timeout: 20 });
  };

  const parseFrontMatter = (raw) => {
    const m = raw.match(/^﻿?---\s*\n([\s\S]*?)\n---\s*\n?/);
    const meta = {};
    let body = raw;
    if (m) {
      body = raw.slice(m[0].length);
      for (const line of m[1].split("\n")) {
        const kv = line.match(/^([A-Za-z0-9_]+)\s*:\s*(.*)$/);
        if (kv) meta[kv[1].toLowerCase()] = kv[2].trim().replace(/^["']|["']$/g, "");
      }
    }
    return { meta: meta, body: body.trim() };
  };

  try {
    const q = encodeURIComponent("org:" + ORG + " topic:" + TOPIC + " fork:true is:public");
    const search = gh(
      "https://api.github.com/search/repositories?q=" + q + "&per_page=100&sort=updated",
      "application/vnd.github+json"
    );
    if (search.statusCode !== 200) throw new Error("github search http " + search.statusCode);

    // private repos never belong in the gallery. Anonymous search can't see
    // them anyway; the is:public qualifier + this filter keep that true if a
    // GITHUB_TOKEN is ever configured.
    const repos = (search.json.items || []).filter((r) => !r.private);
    const apps = repos.map((r) => {
      let meta = {};
      let body = "";
      try {
        // raw media type: README arrives as plain text, no base64 dance
        const res = gh("https://api.github.com/repos/" + r.full_name + "/readme",
          "application/vnd.github.raw+json");
        if (res.statusCode === 200) {
          const parsed = parseFrontMatter(toString(res.body));
          meta = parsed.meta;
          body = parsed.body;
        }
      } catch (_) { /* no readme / mid-flight failure: degrade to repo metadata */ }
      const slug = (meta.slug || r.name).toLowerCase();
      return {
        slug: slug,
        title: meta.title || r.name,
        description: meta.description || r.description || "",
        emoji: meta.emoji || "🕹️",
        url: "https://" + slug + ".solhann.net",
        repo: r.html_url,
        readme: body,
      };
    });

    const payload = JSON.stringify(apps);
    store.set("gallery_json_v2", payload);
    store.set("gallery_t_v2", Date.now());
    return e.json(200, expose(apps));
  } catch (err) {
    if (cachedJSON) {
      return e.json(200, expose(JSON.parse(cachedJSON))); // stale beats broken
    }
    return e.json(502, { error: "gallery discovery failed" });
  }
});
