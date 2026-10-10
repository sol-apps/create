---
name: create-app
description: Scaffold and ship a new solhann.net mini-app. Use whenever the user wants to create/start/make a new app, page, or mini-app on solhann.net (e.g. "create app bat-quiz", "new solhann app", "scaffold a swarm sim app"). Creates a public sol-apps GitHub repo from the on-brand template, tags it `solhann-app`, and pushes so it auto-deploys to <slug>.solhann.net and appears on create.solhann.net.
---

# create-app

One command takes a new app from nothing to live at `https://<slug>.solhann.net`.

## What it does
1. Scaffolds an on-brand starter into the apps folder (`~/Documents/webapps/<slug>/`):
   `index.html`, a README whose front matter feeds the gallery, and a 15-line deploy caller.
2. Creates the **public** repo `sol-apps/<slug>` and pushes. **The push is the deploy**: the
   caller runs `sol-apps/create/.github/workflows/simple.yml`, and the first run creates
   the app on prod — the site, and for `--backend pocketbase` its own PocketBase too.
3. Tags it `solhann-app` (gallery) and `owner-built`, and sets its homepage.
4. **Verifies, doesn't assume:** waits for the Actions run to go green, then polls the live
   URL until HTTP 200 (and `/api/health` for a PocketBase app). It exits non-zero if any of
   that fails — "the script finished" and "the app is live" are the same claim.

No access modes, spec.json, branch protection, environments or provisioning step: a
plain `git push` to `main` is the whole deploy.

## Usage
Gather three things (ask if missing): **slug** (lowercase-hyphenated, = subdomain),
**title**, **description**. Add `--backend pocketbase` for persistent data.

```bash
bash ~/.claude/skills/create-app/create-app.sh [--backend pocketbase] <slug> "<title>" "<description>"
```

Example:
```bash
bash ~/.claude/skills/create-app/create-app.sh bat-quiz "Bat Quiz" "How well do you know bats?"
```

## Backend (`--backend pocketbase`)
Each backed app gets its **own PocketBase** on prod (`pocketbase@<slug>`, same origin
behind Caddy), created by its first deploy.

- **One login for every app**: `admin@solhann.net` and the shared password
  (set on prod with `ssh -t prod 'sudo owner-password'`). It opens the dashboard at
  `https://<slug>.solhann.net/_/`, and in the app `PBAuth.signIn(password)` (the scaffold's
  `pb-auth.js`) signs the browser in as that same superuser. A collection with its rule
  left empty is yours alone; open a rule only for what visitors may do.
- **Schema → `pb_migrations/`.** Edit it on a LOCAL PocketBase: `pb-dev` (on `PATH`) from
  the app checkout serves the app at `127.0.0.1:8090` with its dashboard at `/_/`; clicking
  there writes migration files into `./pb_migrations/`. Commit and push; prod applies them
  (snapshot → migrate → quarantine failures → health check). The scaffold's one migration
  closes PocketBase's default open sign-up — delete it if the app wants public accounts.
- **Server code → `pb_hooks/`.** Delivered on every push and hot-reloaded; deleting a file
  deletes it on prod. Goja VM: PocketBase's helpers only (`$app`, `$http`, `$os`,
  `cronAdd`, `routerAdd`, …), no npm.
- **Runtime secrets** (never committed): `pb-secret set <slug>.MY_KEY`, then
  `push-secrets <slug>`; hooks read `$os.getenv("MY_KEY")`.
- **Backups:** in the dashboard, Settings → Backups.

Each instance runs as its own `pb-<slug>` user in a sandboxed, resource-limited unit, so a
broken hook stays inside its own app. PocketBase slugs are capped at 28 characters.

## Working style
Run the whole flow — scaffold, build the actual app, push, verify live — without pausing
to ask whether to continue. The only genuine stops are missing auth (`gh` not logged in) or
a deploy the script can't recover; surface those with the error output. When iterating
after scaffold, don't report a change as done until it's pushed AND confirmed live (deploy
green + the change visible at the URL, e.g. `curl`).

## Notes
- A repo made by hand works the same way: give it the caller
  (`template/deploy.yml` here) and push.
- Apps must be **public**: org-level Actions secrets only reach public repos on this plan.
- The gallery features a new app on create.solhann.net's front page by default and caches
  discovery for ~15 min, so a brand-new tile can lag briefly. To take an app off the front
  page, add its slug to `NOT_FEATURED` in the `create` repo's `pb_hooks/gallery.pb.js`.
- **Known transients (retry, don't debug):** concurrent deploys of different apps can hit
  the shared rrsync lock (the workflow retries); a new app's certificate takes up to a
  minute; pushing a changed `pb_hooks/` file makes PB reload, so `/api/*` can 502 for a
  moment.
- Browser caching: HTML is always fresh, and the pipeline's `?v=<sha>` cache-bust handles
  `.js`/`.css` — if a change "isn't showing", check with `curl` before suspecting the deploy.
- A top-level `kit/` folder in a repo is never published (that is where `create` keeps
  this skill and its tools).
- The skill's source is `create/kit/skill/create-app/`; after editing it, run
  `kit/skill/install-skill.sh` to refresh the copy Claude Code uses.
