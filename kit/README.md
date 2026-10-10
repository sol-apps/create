# kit — what the solhann.net apps are made and run with

Everything outside an app's own repo that the apps need. It lives in `create` because
the gallery and the tooling are the same idea: this is the home of the apps. Nothing
under `kit/` is ever published to a site (the deploy workflow leaves it out).

    .github/workflows/simple.yml   the deploy every app calls: a push to main goes live,
                                   and a new repo's first push creates the app
    kit/skill/create-app/          the Claude Code skill that makes a new app
    kit/skill/install-skill.sh     copies the skill to ~/.claude/skills after an edit
    kit/bin/pb-dev                 run an app locally with its own PocketBase
    kit/bin/pb-secret              the laptop's secrets store
    kit/bin/push-secrets           send an app's runtime secrets to prod
    kit/server/                    the scripts prod runs for these apps

## An app

A public repo in `sol-apps` named for its address, `<slug>.solhann.net`:

- `index.html`, and whatever else the page needs
- `.github/workflows/deploy.yml`, the caller (`kit/skill/create-app/template/deploy.yml`)
- `README.md`, whose front matter (`title`, `description`) is what the gallery shows
- with a database: `pb-auth.js`, `pb_hooks/`, `pb_migrations/`

`create-app.sh [--backend pocketbase] <slug> "<title>" "<description>"` makes one and
waits until it is live.

## The server

`kit/server/` is a copy of what is installed on prod: `owner-lane` (the only command
the deploy key may run), `owner-app` (gives a new app its PocketBase), `owner-password`
(the one dashboard password, typed on prod and never read back) and `install.sh`.
As of 2026-10-10 prod still runs the copies installed from the old location; these
become the source when they are next installed from here.
