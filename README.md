# create.solhann.net — the app gallery

The hub of the [solhann.net](https://solhann.net) platform: a flip-card gallery of every
mini-app deployed on it. Repos in the `sol-apps` org tagged with the `solhann-app` topic
appear here automatically — title, description and emoji come from the YAML front matter
of each repo's README, and the README itself renders on the card's back face.

This repo is deliberately **not** tagged `solhann-app`: the gallery doesn't list itself.

## How it works

Plain static files, no build step — the standard platform app shape:

- `index.html` + `styles.css` + `app.js` — the flip-card UI (retro-arcade / neo-brutalist,
  light/dark toggle). The client makes exactly one same-origin call: `GET /api/gallery`.
- `pb_hooks/gallery.pb.js` — this app's PocketBase instance answers `/api/gallery` by
  proxying the GitHub org search + per-repo READMEs server-side, with a 15-minute
  in-process cache (stale served on upstream failure). Visitors never touch GitHub's
  anonymous rate limit.
- `pb-auth.js` — the platform's standard identity seam, unused by the gallery today but
  in place for real auth later (it also marks the repo as PocketBase-backed so CI runs
  the `pb_hooks` delivery lane).

## Deploys

Push to `main` → the thin caller in `.github/workflows/deploy.yml` runs the shared
pipeline in [`sol-apps/workflows`](https://github.com/sol-apps/workflows): statics rsync
to the web root, `pb_hooks/` ships over the write-only hooks lane, assets get
cache-busted with `?v=<sha>`. Live at <https://create.solhann.net> in ~30s.

If GitHub's anonymous API budget ever gets tight, give the hook a token (from the dev
box): `pb-secret set create.GITHUB_TOKEN` then `pb-provision create --push-env`.
