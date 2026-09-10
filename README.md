# create.solhann.net — the app gallery

The hub of the [solhann.net](https://solhann.net) platform: a card gallery of a curated
set of the mini-apps deployed on it. Discovery is automatic — repos in the `sol-apps` org
tagged with the `solhann-app` topic, titled from their README's YAML front matter — but
the page asks for `/api/gallery?featured=1`, which returns only the apps in `FEATURED` in
`pb_hooks/gallery.pb.js`. The cheat code shows everything. The unfiltered route is
unchanged because the greenlight shelf reads it.

## Deploys

Push to `main` → the thin caller in `.github/workflows/deploy.yml` runs the shared
pipeline in [`sol-apps/workflows`](https://github.com/sol-apps/workflows): statics rsync
to the web root, `pb_hooks/` ships over the write-only hooks lane, assets get
cache-busted with `?v=<sha>`. Live at <https://create.solhann.net> in ~30s.

