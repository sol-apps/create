#!/usr/bin/env bash
# create-app.sh — a new solhann.net app, live: scaffold it, make its repo, push.
#   usage: create-app.sh [--backend pocketbase] <slug> <title> <description>
#   e.g.:  create-app.sh bat-quiz "Bat Quiz" "How well do you know bats?"
#
# The push is the whole deploy. The repo's caller runs sol-apps/create's simple.yml,
# whose first run creates the app on prod: the site, and with --backend pocketbase its own
# PocketBase, whose dashboard (/_/) takes admin@solhann.net and the password every app
# shares. This script then waits for that run and for the live URL, because "pushed"
# is not "live".
set -euo pipefail

ORG="sol-apps"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/template"
# Everything a new app starts from is in template/, the PocketBase SDK included, so this
# runs the same in place (create/kit/skill/create-app/) and as the installed skill.
PB_SDK="$TEMPLATE/vendor/pocketbase.umd.js"
# New apps go in the apps folder (SOLHANN_PROJECTS overrides).
PROJECTS="${SOLHANN_PROJECTS:-$HOME/Documents/webapps}"

usage() {
  echo "usage: create-app.sh [--backend pocketbase] <slug> <title> <description>"
  exit 2
}
BACKEND="none"
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --backend) [ "$#" -ge 2 ] || usage; BACKEND="$2"; shift 2 ;;
    --access|--governed)
      echo "✗ $1 is gone: these apps have no access modes. A PocketBase app's" >&2
      echo "  login is the shared superuser one (pb-auth.js); everything else is public." >&2
      exit 2 ;;
    --*) echo "✗ unknown option '$1'" >&2; usage ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
[ "${#ARGS[@]}" -eq 3 ] || usage
SLUG="${ARGS[0]}"; TITLE="${ARGS[1]}"; DESC="${ARGS[2]}"
case "$BACKEND" in none|pocketbase) ;; *) echo "✗ unknown backend '$BACKEND' (only: pocketbase)"; exit 1 ;; esac

# --- validation ---
if ! [[ "$SLUG" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || [ "${#SLUG}" -gt 63 ]; then
  echo "✗ slug must be lowercase letters/digits/hyphens, max 63 chars (e.g. 'bat-quiz')"; exit 1
fi
if [ "$BACKEND" = "pocketbase" ] && [ "${#SLUG}" -gt 28 ]; then
  echo "✗ pocketbase-backed slugs max out at 28 chars (the pb-<slug> unix user must fit 32)"; exit 1
fi
if [ "$BACKEND" = "pocketbase" ] && [ ! -f "$PB_SDK" ]; then
  echo "✗ no PocketBase SDK at $PB_SDK — reinstall the skill (kit/skill/install-skill.sh)"; exit 1
fi
[ -d "$PROJECTS" ] || { echo "✗ no apps folder at $PROJECTS (set SOLHANN_PROJECTS)"; exit 1; }
command -v gh >/dev/null || { echo "✗ gh is not installed"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "✗ gh is not authenticated (run: gh auth login)"; exit 1; }
if gh repo view "$ORG/$SLUG" >/dev/null 2>&1; then echo "✗ repo $ORG/$SLUG already exists"; exit 1; fi
DEST="$PROJECTS/$SLUG"
[ -e "$DEST" ] && { echo "✗ $DEST already exists locally"; exit 1; }

# --- scaffold (literal, regex-free substitution so titles/descriptions are safe) ---
echo "▸ scaffolding $ORG/$SLUG in $DEST …"
mkdir -p "$DEST/.github/workflows"
subst() {
  local c; c="$(cat "$1")"
  c="${c//\{\{SLUG\}\}/$SLUG}"
  c="${c//\{\{TITLE\}\}/$TITLE}"
  c="${c//\{\{DESCRIPTION\}\}/$DESC}"
  printf '%s\n' "$c" > "$2"
}
subst "$TEMPLATE/index.html" "$DEST/index.html"
subst "$TEMPLATE/README.md"  "$DEST/README.md"
cp "$TEMPLATE/deploy.yml" "$DEST/.github/workflows/deploy.yml"

if [ "$BACKEND" = "pocketbase" ]; then
  mkdir -p "$DEST/vendor" "$DEST/pb_hooks" "$DEST/pb_migrations"
  cp "$PB_SDK" "$DEST/vendor/pocketbase.umd.js"
  subst "$TEMPLATE/pb-auth.js" "$DEST/pb-auth.js"
  subst "$TEMPLATE/pb_hooks/main.pb.js" "$DEST/pb_hooks/main.pb.js"
  cp "$TEMPLATE"/pb_migrations/*.js "$DEST/pb_migrations/"
  printf '.pb_data/\n' >> "$DEST/.gitignore"
  # Inject the SDK + auth scripts ahead of </head>. Shell splitting rather than `sed -i`:
  # BSD sed needs a backup suffix and doesn't expand \n in the replacement, and both sed
  # and ${v/pat/repl} read & as "the whole match".
  html=$(cat "$DEST/index.html")
  case "$html" in *"</head>"*) ;; *) echo "✗ template index.html has no </head>" >&2; exit 1 ;; esac
  inject='  <script src="vendor/pocketbase.umd.js"></script>
  <script src="pb-auth.js"></script>
</head>'
  printf '%s%s%s\n' "${html%%</head>*}" "$inject" "${html#*</head>}" > "$DEST/index.html"
fi

# --- repo + push: the push is the deploy ---
cd "$DEST"
git init -b main -q
git config user.name  "SolHann"
git config user.email "14826882+SolHann@users.noreply.github.com"
git add -A
git commit -qm "Scaffold $SLUG — $TITLE"

echo "▸ creating $ORG/$SLUG and pushing (the push deploys it) …"
gh repo create "$ORG/$SLUG" --public --description "$DESC" --source=. --remote=origin --push >/dev/null
# solhann-app lists it in the gallery; owner-built is what the server reads to tell it
# from an app another system on the same box built.
gh repo edit "$ORG/$SLUG" --homepage "https://$SLUG.solhann.net" \
  --add-topic solhann-app --add-topic owner-built >/dev/null

# --- verify (deploy green, site live, backend healthy; never assume) ---
echo "▸ waiting for the deploy …"
RUN_ID=""
for _ in $(seq 1 24); do
  RUN_ID="$(gh run list --repo "$ORG/$SLUG" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
  [ -n "$RUN_ID" ] && break
  sleep 5
done
[ -n "$RUN_ID" ] || { echo "✗ no workflow run appeared — check https://github.com/$ORG/$SLUG/actions"; exit 1; }
gh run watch --repo "$ORG/$SLUG" "$RUN_ID" --exit-status >/dev/null \
  || { echo "✗ deploy failed — gh run view --repo $ORG/$SLUG $RUN_ID --log-failed"; exit 1; }

probe() { # probe <url> — until HTTP 200 (a new app's certificate and PB reloads take a moment)
  local url="$1" code=""
  for _ in $(seq 1 24); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
    [ "$code" = "200" ] && return 0
    sleep 5
  done
  echo "✗ $url not healthy (last HTTP ${code:-none})"; return 1
}
probe "https://$SLUG.solhann.net/"
[ "$BACKEND" = "pocketbase" ] && probe "https://$SLUG.solhann.net/api/health"

cat <<EOF

✓ $TITLE is live
  site : https://$SLUG.solhann.net
  repo : https://github.com/$ORG/$SLUG
  local: $DEST   (commit + git push = deploy)
EOF
if [ "$BACKEND" = "pocketbase" ]; then
  cat <<EOF
  data : https://$SLUG.solhann.net/_/   (admin@solhann.net, the shared password)
  next : make collections LOCALLY — cd $DEST && pb-dev — then commit the generated
         pb_migrations/ and push. In the app, PBAuth.signIn(password) is the same login.
         Secrets: pb-secret set $SLUG.MY_KEY, then push-secrets $SLUG
EOF
fi
