# create.solhann.net

The hub / gallery for the **solhann.net** mini-app platform. It discovers every repo in the
[`sol-apps`](https://github.com/sol-apps) org tagged with the `solhann-app` topic, reads each
app's README front matter, and renders it as a card. Click a card to launch the app at
`https://<slug>.solhann.net`.

- **Static** (HTML/CSS/JS, no build), deployed through the standard solhann pipeline
  (`git push` → GitHub Actions → rsync → `/var/www/apps/create/`).
- **Runtime discovery** via the GitHub API (no rebuild needed when apps are added).
- This repo is intentionally **not** tagged `solhann-app` — the hub shouldn't list itself.
