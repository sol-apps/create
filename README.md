# create.solhann.net

The hub / gallery for the **solhann.net** mini-app platform. It discovers every repo in the
[`sol-apps`](https://github.com/sol-apps) org tagged with the `solhann-app` topic, reads each
app's README front matter, and renders it as a card. Click a card to launch the app at
`https://<slug>.solhann.net`.

## Stack

- **TypeScript** (strict) + **Vite** for bundling, type-checking, and dev server.
- **Static output**: `vite build` emits `dist/` with hashed asset filenames.
- **Runtime discovery** via the GitHub API (no rebuild needed when apps are added).
- This repo is intentionally **not** tagged `solhann-app` — the hub shouldn't list itself.

## Scripts

```bash
npm install      # one-time
npm run dev      # dev server with HMR
npm run build    # type-check + bundle into dist/
npm run preview  # serve the production build locally
```

## Layout

```
src/
  main.ts            # entry — wires up theme + gallery
  theme.ts           # dark/light toggle, persisted to localStorage
  gallery.ts         # discover, cache, render, interactions
  github.ts          # tiny GH API wrapper + front-matter parser
  markdown.ts        # safe-ish README → HTML
  styles/
    base.css         # tokens, reset, scanlines, shared chip
    layout.css       # topbar + masthead
    card.css         # gallery grid + card front + buttons
    readme.css       # card back face + rendered markdown
    states.css       # skeleton loader + empty/error notice
index.html           # Vite entry — loads /src/main.ts
```

## Deploy

GitHub Actions builds on push to `main` and rsyncs `dist/` to `/var/www/apps/create/` on
the solhann server.
