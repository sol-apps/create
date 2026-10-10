# create.solhann.net — the app gallery, and the apps' kit

Two things, one idea: this is the home of the apps on [solhann.net](https://solhann.net).

**The gallery.** A card for each app. Discovery is automatic: public repos in the
`sol-apps` org tagged `solhann-app` and served on solhann.net, titled from the front
matter of their README. A new app is on the front page by default; to take one off it,
add its slug to `NOT_FEATURED` in `pb_hooks/gallery.pb.js` and push. The cheat code shows
those too.

**The kit.** What the apps are made and run with: the deploy workflow every app calls
(`.github/workflows/simple.yml`), the `create-app` skill, and the local tools. See
[kit/README.md](kit/README.md). Nothing under `kit/` is published to the site.

## Deploys

A push to `main` is the deploy, here as for every app: the site is copied to the web
root, `pb_hooks/` goes to this app's PocketBase, and `.js`/`.css` links get `?v=<sha>`.
Live at <https://create.solhann.net> in about 30 seconds.
