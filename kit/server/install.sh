#!/usr/bin/env bash
# install.sh — the owner's simple lane, on prod. Root. Run from the staged bundle:
#
#   ssh -t prod 'sudo bash ~/greenlit-migration/platform/prod/owner/install.sh'
#   ssh -t prod 'sudo bash ~/greenlit-migration/platform/prod/owner/install.sh --rollback'
#
# 1. installs owner-lane, owner-app and owner-password in /usr/local/bin, and a sudoers
#    rule letting sol (the CI key's forced command) run owner-app;
# 2. the first time, asks for the one /_/ password every owner app shares, and applies it
#    (owner-password);
# 3. moves the org-wide CI key — GitHub org secret SERVER_SSH_KEY — from
#    `rrsync -wo -munge /var/www/apps` to owner-lane. owner-lane's rsync branch is that
#    same command, so every existing deploy, Greenlight's included, carries on unchanged;
#    what the key gains is owner-lane's two owner verbs.
# 4. checks the lane as CI will meet it: Greenlight's apps refused, an owner app accepted.
#
# Idempotent. --rollback puts the key's old command back; the tools stay, inert without it.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
AK=/home/sol/.ssh/authorized_keys
LANE='command="/usr/local/bin/owner-lane"'
STATIC='command="rrsync -wo -munge /var/www/apps"'
BK=/var/backups/greenlit/owner-lane-$(date -u +%Y%m%dT%H%M%SZ)
TOOLS="owner-lane owner-app owner-password"

die() { echo "✗ $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root: sudo bash $0"

# replace_once <from> <to> — swap one exact string in authorized_keys, keeping a backup.
replace_once() {
  install -d -m 700 "$BK"
  cp -p "$AK" "$BK/authorized_keys"
  local tmp; tmp=$(mktemp)
  FROM="$1" TO="$2" python3 -c 'import os,sys; s=sys.stdin.read(); print(s.replace(os.environ["FROM"], os.environ["TO"], 1), end="")' \
    < "$AK" > "$tmp"
  if [ "$(grep -cF "$2" "$tmp")" != 1 ] || [ "$(grep -c '' "$tmp")" != "$(grep -c '' "$AK")" ]; then
    rm -f "$tmp"; die "authorized_keys rewrite looked wrong; unchanged"
  fi
  install -m 600 -o sol -g sol "$tmp" "$AK"
  rm -f "$tmp"
}

if [ "${1:-}" = --rollback ]; then
  n=$(grep -cF "$LANE" "$AK" || true)
  [ "$n" = 1 ] || die "expected one owner-lane line in $AK, found $n; nothing changed"
  replace_once "$LANE" "$STATIC"
  echo "✓ the org CI key is back on the plain static lane (previous file in $BK)"
  echo "  owner apps' sites still deploy; their backends and new apps do not, until install.sh runs again"
  exit 0
fi
[ "$#" = 0 ] || die "usage: install.sh [--rollback]"

# ── preflight ───────────────────────────────────────────────────────────────
[ -x /usr/local/bin/pb-deploy-jail ] || die "pb-deploy-jail is missing; this box was not bootstrapped"
[ -x /usr/local/bin/pocketbase ] || die "pocketbase is missing"
command -v rrsync >/dev/null || [ -x /usr/bin/rrsync ] || die "rrsync is missing"
command -v setfacl >/dev/null || die "setfacl is missing (acl package)"
grep -q '^OWNER_DOMAIN=.' /etc/greenlight/instance.conf 2>/dev/null \
  || die "/etc/greenlight/instance.conf names no OWNER_DOMAIN"
for t in $TOOLS; do
  [ -f "$HERE/$t" ] || die "$HERE/$t is missing; stage the bundle whole"
done
sh -n "$HERE/owner-lane"
bash -n "$HERE/owner-app"
bash -n "$HERE/owner-password"

# ── 1. tools, sudoers, and what owner-lane reads ────────────────────────────
# owner-lane runs as sol and decides from these two files, which hold only domain names.
for f in /etc/greenlight/instance.conf /etc/greenlight/hosts; do
  [ -f "$f" ] && chmod 644 "$f"
done

for t in $TOOLS; do
  if cmp -s "$HERE/$t" "/usr/local/bin/$t"; then
    echo "  = /usr/local/bin/$t"
  else
    install -m 755 -o root -g root "$HERE/$t" "/usr/local/bin/$t"
    echo "▸ installed /usr/local/bin/$t"
  fi
done
SUDOF=/etc/sudoers.d/owner-lane
tmp=$(mktemp)
printf '%s\n' \
  "# The org CI key's forced command (owner-lane) may set up an owner app's PocketBase." \
  "sol ALL=(root) NOPASSWD: /usr/local/bin/owner-app" > "$tmp"
visudo -cf "$tmp" >/dev/null || { rm -f "$tmp"; die "sudoers rule failed visudo"; }
if cmp -s "$tmp" "$SUDOF"; then
  echo "  = $SUDOF"
else
  install -m 440 -o root -g root "$tmp" "$SUDOF"
  echo "▸ $SUDOF: sol may run owner-app"
fi
rm -f "$tmp"

# ── 2. the shared password ──────────────────────────────────────────────────
if [ -s /etc/pocketbase/owner.superuser ]; then
  echo "  = shared /_/ password already set (change it any time: sudo owner-password)"
else
  echo "▸ choose the one password for /_/ on every owner app"
  /usr/local/bin/owner-password
fi

# ── 3. the org CI key ───────────────────────────────────────────────────────
if grep -qF "$LANE" "$AK"; then
  echo "  = the org CI key already runs owner-lane"
else
  cur=$(grep -oE 'command="rrsync( -[a-z-]+)* /var/www/apps"' "$AK" || true)
  [ -n "$cur" ] || die "no static-lane key in $AK; nothing changed"
  [ "$(printf '%s\n' "$cur" | grep -c .)" = 1 ] || die "more than one static-lane key in $AK; nothing changed"
  [ "$cur" = "$STATIC" ] || die "the static lane is '$cur', not write-only: run harden-lanes.sh first"
  replace_once "$STATIC" "$LANE"
  echo "▸ the org CI key now runs owner-lane (previous file in $BK)"
fi

# ── 4. the lane as CI meets it ──────────────────────────────────────────────
OWNER_DOMAIN=$(sed -n 's/^OWNER_DOMAIN=//p' /etc/greenlight/instance.conf | tail -1)
lane() { sudo -u sol env SSH_ORIGINAL_COMMAND="$1" /usr/local/bin/owner-lane </dev/null 2>&1 || true; }
pass=0; fail=0
expect() { # expect <label> <text the answer must contain> <answer>
  case "$3" in
    *"$2"*) echo "  ✓ $1"; pass=$((pass + 1)) ;;
    *) echo "  ✗ $1: $3"; fail=$((fail + 1)) ;;
  esac
}
echo "checks:"
expect "an unknown command is refused" "denied" "$(lane 'ls /')"
expect "a malformed slug is refused" "denied" "$(lane 'provision ../etc')"
# owner-app's own refusal, which also proves the sudo rule lets the lane reach it
gl=$(awk -v d="$OWNER_DOMAIN" 'NF >= 2 && $2 !~ ("\\." d "$") { print $1; exit }' /etc/greenlight/hosts)
if [ -n "$gl" ]; then
  expect "Greenlight's $gl cannot be set up as an owner app" "not one of the owner's apps" \
    "$(lane "provision $gl")"
  expect "Greenlight's $gl takes no server code from this key" "not one of the owner's apps" \
    "$(lane "pb-rsync --server -logDtprce.iLsfxCIvu --delete . $gl/")"
fi
mine=""
while read -r s h _; do
  [ "$h" = "$s.$OWNER_DOMAIN" ] && [ -f "/etc/pocketbase/$s.env" ] && { mine=$s; break; }
done < /etc/greenlight/hosts
if [ -n "$mine" ]; then
  expect "owner app $mine is recognised as set up" "already set up" "$(lane "provision $mine")"
  # Its server code gets through owner-lane, pb-deploy-jail and rrsync to rsync itself.
  # With nothing on stdin the rsync server sees only the stream end ("connection
  # unexpectedly closed", code 12) and writes nothing; a refusal says denied or rrsync error.
  expect "owner app $mine's server code reaches its jail" "connection unexpectedly closed" \
    "$(lane "pb-rsync --server -logDtprce.iLsfxCIvu . $mine/")"
fi
echo "$pass passed, $fail failed"
[ "$fail" = 0 ] || die "a check failed; to undo: sudo bash $0 --rollback"
echo "✓ done: a push to an owner app deploys it, a new repo's first push creates it, and"
echo "  /_/ on every $OWNER_DOMAIN app takes admin@solhann.net with the shared password"
