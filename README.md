# create.solhann.net — the app gallery

The hub of the [solhann.net](https://solhann.net) platform: a flip-card gallery of every
mini-app deployed on it. Repos in the `sol-apps` org tagged with the `solhann-app` topic
appear here automatically — title, description and emoji come from the YAML front matter
of each repo's README, and the README itself renders on the card's back face.

## Deploys

Push to `main` → the thin caller in `.github/workflows/deploy.yml` runs the shared
pipeline in [`sol-apps/workflows`](https://github.com/sol-apps/workflows): statics rsync
to the web root, `pb_hooks/` ships over the write-only hooks lane, assets get
cache-busted with `?v=<sha>`. Live at <https://create.solhann.net> in ~30s.

