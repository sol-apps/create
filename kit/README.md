# kit — what the solhann.net apps are made and run with

Everything outside an app's own repo that the apps need. It lives in `create` because
the gallery and the tooling are the same idea: this is the home of the apps. Nothing
under `kit/` is ever published to a site (the deploy workflow leaves it out).

    .github/workflows/simple.yml   the deploy every app calls: a push to main goes live,
                                   and a new repo's first push creates the app
    kit/skill/create-app/          the Claude Code skill that makes a new app
    kit/skill/forum/               the skill for reading and posting to forum.solhann.net
    kit/skill/install-skill.sh     copies the skills to ~/.claude/skills after an edit
    kit/bin/pb-dev                 run an app locally with its own PocketBase
    kit/bin/pb-secret              the laptop's secrets store
    kit/bin/push-secrets           send an app's runtime secrets to prod
    kit/bin/forum                  read and post to the forum from a terminal
    kit/server/                    the scripts prod runs for these apps
    kit/tests/                     create-app and the server scripts, run for real against stand-ins

## An app

A public repo in `sol-apps` named for its address, `<slug>.solhann.net`:

- `index.html`, and whatever else the page needs
- `.github/workflows/deploy.yml`, the caller (`kit/skill/create-app/template/deploy.yml`)
- `README.md`, whose front matter (`title`, `description`) is what the gallery shows
- with a database: `pb-auth.js`, `pb_hooks/`, `pb_migrations/`

`create-app.sh [--backend pocketbase] <slug> "<title>" "<description>"` makes one and
waits until it is live.

## The server

`kit/server/` is what prod runs for these apps, installed from here:

    scp -r kit/server prod:solhann-kit/     (or however the folder gets there)
    ssh -t prod 'sudo bash ~/solhann-kit/server/install.sh'

- `owner-lane` — the only command the deploy key may run: publish a site, deliver an
  app's `pb_hooks/` and `pb_migrations/`, or ask for an app's PocketBase.
- `owner-app` — gives a new app its PocketBase. A no-op once it has one.
- `owner-password` — the one dashboard password, typed on prod and never read back.
- `owner-env` — replaces an app's runtime secrets; `push-secrets` calls it.
- `adopt-app` — run by hand, once per app: takes an app that already runs on this box
  at another address and makes it one of these (new address, old one redirects, shared
  password). Its data and port are untouched; `--rollback` undoes it.
- `install.sh` — installs those five, keeps what they replace under
  `/var/backups/solhann/`, and has `--rollback`.

They go by two files on prod: `/etc/solhann/conf` (the domain) and `/etc/solhann/apps`
(one line per app with a PocketBase). The box is shared with other things, so `conf`
also says where to look for names already taken; the scripts themselves name nobody.
Underneath, the box's own PocketBase service unit, migrations watcher and write-only
deploy jails are used as they are.

`bash kit/tests/test-server.sh` runs all five against a throwaway tree.
