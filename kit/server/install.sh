#!/usr/bin/env bash
# install.sh — the solhann.net apps' side of prod. Root. Run from the staged copy of
# this folder:
#
#   ssh -t prod 'sudo bash ~/solhann-kit/server/install.sh'
#   ssh -t prod 'sudo bash ~/solhann-kit/server/install.sh --rollback'
#
# 1. /etc/solhann/conf (the domain, and where to look for names something else on this
#    box has) and /etc/solhann/apps (the apps: "<slug> <host>"). Both are made once and
#    then left alone. The first time, apps is filled from the record the box already
#    keeps: every app recorded at <slug>.<DOMAIN> that has a PocketBase.
# 2. installs owner-lane, owner-app, owner-password and owner-env, plus adopt-app and
#    remove-app (both run by hand: take over an app already on this box; take one off
#    it) in /usr/local/bin, and
#    the sudoers rule that lets sol run owner-app (the deploy) and owner-env
#    (push-secrets). What they replace is kept under /var/backups/solhann/.
# 3. takes settings these apps no longer read out of their environment files.
# 4. checks the lane as a deploy will meet it.
#
# Idempotent. It expects the deploy key to run owner-lane already and the shared /_/
# password to be set; it says so and stops if not. --rollback puts back the scripts and
# the sudoers rule from the most recent backup; /etc/solhann stays.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
AK=/home/sol/.ssh/authorized_keys
ETC=/etc/pocketbase
CONFDIR=/etc/solhann
CONF=$CONFDIR/conf
APPS=$CONFDIR/apps
SUDOF=/etc/sudoers.d/owner-lane
BKROOT=/var/backups/solhann
TOOLS="owner-lane owner-app owner-password owner-env adopt-app remove-app"
DEFAULT_DOMAIN=solhann.net
# Looked at once, to write conf and to fill apps; the scripts go by /etc/solhann only.
NEIGHBOUR_HOSTS=/etc/greenlight/hosts
NEIGHBOUR_FORGE_CONF=/etc/forgejo/app.ini
NEIGHBOUR_FORGE=http://127.0.0.1:3000/api/v1/repos/sol-apps

die() { echo "✗ $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root: sudo bash $0"

if [ "${1:-}" = --rollback ]; then
  [ "$#" = 1 ] || die "usage: install.sh [--rollback]"
  last=$(ls -1d "$BKROOT"/server-* 2>/dev/null | sort | tail -1)
  [ -n "$last" ] || die "no backup under $BKROOT; nothing changed"
  for t in $TOOLS; do
    if [ -f "$last/$t" ]; then
      install -m 755 -o root -g root "$last/$t" "/usr/local/bin/$t"; echo "▸ restored /usr/local/bin/$t"
    elif [ -f "/usr/local/bin/$t" ]; then
      rm -f "/usr/local/bin/$t"; echo "▸ removed /usr/local/bin/$t (it was not there before)"
    fi
  done
  if [ -f "$last/sudoers" ]; then
    visudo -cf "$last/sudoers" >/dev/null || die "the saved sudoers rule fails visudo; left as it is"
    install -m 440 -o root -g root "$last/sudoers" "$SUDOF"; echo "▸ restored $SUDOF"
  fi
  echo "✓ back to the scripts saved in $last ($CONFDIR is left in place; environment files"
  echo "  are in the same backup if you want them back)"
  exit 0
fi
[ "$#" = 0 ] || die "usage: install.sh [--rollback]"

# ── preflight ───────────────────────────────────────────────────────────────
[ -x /usr/local/bin/pb-deploy-jail ] || die "pb-deploy-jail is missing; this box has no PocketBase lane"
[ -x /usr/local/bin/pocketbase ] || die "pocketbase is missing"
command -v rrsync >/dev/null || [ -x /usr/bin/rrsync ] || die "rrsync is missing"
command -v setfacl >/dev/null || die "setfacl is missing (acl package)"
for t in $TOOLS; do
  [ -f "$HERE/$t" ] || die "$HERE/$t is missing; stage the folder whole"
done
sh -n "$HERE/owner-lane"
for t in owner-app owner-password owner-env adopt-app remove-app; do bash -n "$HERE/$t"; done
grep -qF 'command="/usr/local/bin/owner-lane"' "$AK" \
  || die "the deploy key does not run owner-lane in $AK; nothing changed"
[ -s "$ETC/owner.superuser" ] \
  || die "no shared /_/ password yet; nothing changed (it is set with: sudo owner-password)"

# ── 1. /etc/solhann ─────────────────────────────────────────────────────────
install -d -m 755 -o root -g root "$CONFDIR"
if [ -f "$CONF" ]; then
  echo "  = $CONF"
else
  tmp=$(mktemp)
  {
    echo "# The solhann.net apps on this box. Read by owner-lane, owner-app, owner-password"
    echo "# and owner-env. The apps themselves are listed in $APPS."
    echo "DOMAIN=$DEFAULT_DOMAIN"
    if [ -f "$NEIGHBOUR_HOSTS" ] || [ -f "$NEIGHBOUR_FORGE_CONF" ]; then
      echo "# This box is shared. A new app may not take a name something else here has:"
      echo "# delete these lines if that ever stops being true."
      [ -f "$NEIGHBOUR_HOSTS" ] && echo "TAKEN_HOSTS=$NEIGHBOUR_HOSTS"
      [ -f "$NEIGHBOUR_FORGE_CONF" ] && echo "TAKEN_FORGE=$NEIGHBOUR_FORGE"
    fi
  } > "$tmp"
  install -m 644 -o root -g root "$tmp" "$CONF"; rm -f "$tmp"
  echo "▸ wrote $CONF"
fi
DOMAIN=$(sed -n 's/^DOMAIN=//p' "$CONF" | tail -1)
[ -n "$DOMAIN" ] || die "$CONF names no DOMAIN"

if [ -f "$APPS" ]; then
  echo "  = $APPS ($(grep -c . "$APPS" || true) app(s))"
else
  tmp=$(mktemp)
  if [ -f "$NEIGHBOUR_HOSTS" ]; then
    while read -r s h _; do
      case "$s" in ''|\#*) continue ;; esac
      [ "$h" = "$s.$DOMAIN" ] && [ -f "$ETC/$s.env" ] && printf '%s %s\n' "$s" "$h" >> "$tmp"
    done < "$NEIGHBOUR_HOSTS"
  fi
  install -m 644 -o root -g root "$tmp" "$APPS"; rm -f "$tmp"
  echo "▸ wrote $APPS from the box's existing record:"
  sed 's/^/    /' "$APPS"
fi

# ── 2. the scripts and the sudoers rule ─────────────────────────────────────
BK=$BKROOT/server-$(date -u +%Y%m%dT%H%M%SZ)
install -d -m 700 -o root -g root "$BKROOT" "$BK"
for t in $TOOLS; do
  [ -f "/usr/local/bin/$t" ] && cp -p "/usr/local/bin/$t" "$BK/$t"
done
[ -f "$SUDOF" ] && cp -p "$SUDOF" "$BK/sudoers"

for t in $TOOLS; do
  if cmp -s "$HERE/$t" "/usr/local/bin/$t"; then
    echo "  = /usr/local/bin/$t"
  else
    install -m 755 -o root -g root "$HERE/$t" "/usr/local/bin/$t"
    echo "▸ installed /usr/local/bin/$t"
  fi
done
tmp=$(mktemp)
printf '%s\n' \
  "# The deploy key's only command (owner-lane) may set up an app's PocketBase, and" \
  "# push-secrets, from the laptop, may replace an app's runtime secrets." \
  "sol ALL=(root) NOPASSWD: /usr/local/bin/owner-app, /usr/local/bin/owner-env" > "$tmp"
visudo -cf "$tmp" >/dev/null || { rm -f "$tmp"; die "sudoers rule failed visudo"; }
if cmp -s "$tmp" "$SUDOF"; then
  echo "  = $SUDOF"
else
  install -m 440 -o root -g root "$tmp" "$SUDOF"
  echo "▸ $SUDOF: sol may run owner-app and owner-env"
fi
rm -f "$tmp"

# ── 3. settings these apps no longer read ───────────────────────────────────
# Left in the environment files by the system that used to set these apps up. Nothing
# in the apps reads them now. The file changes; the running app is not restarted, and
# simply stops being handed them the next time it starts.
STALE='^(GREENLIGHT_[A-Z0-9_]*|OIDC_[A-Z0-9_]*)='
while read -r s h _; do
  case "$s" in ''|\#*) continue ;; esac
  f="$ETC/$s.env"
  [ -f "$f" ] || continue
  if grep -qE "$STALE" "$f"; then
    install -d -m 700 "$BK/env"
    cp -p "$f" "$BK/env/$s.env"
    names=$(grep -oE "$STALE" "$f" | tr -d '=' | sort | tr '\n' ' ')
    tmp=$(mktemp)
    grep -vE "$STALE" "$f" > "$tmp" || true
    grep -q '^PB_PORT=' "$tmp" || { rm -f "$tmp"; die "$f would lose PB_PORT; left alone"; }
    install -m 600 -o root -g root "$tmp" "$f"; rm -f "$tmp"
    echo "▸ $s: removed ${names% } from its environment file"
  fi
done < "$APPS"

# ── 4. the lane as a deploy meets it ────────────────────────────────────────
# tr: the rsync server's reply carries a null byte, which bash would warn about.
lane() { sudo -u sol env SSH_ORIGINAL_COMMAND="$1" /usr/local/bin/owner-lane </dev/null 2>&1 | tr -d '\0' || true; }
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
taken=""
TAKEN_HOSTS=$(sed -n 's/^TAKEN_HOSTS=//p' "$CONF" | tail -1)
[ -z "$TAKEN_HOSTS" ] || taken=$(awk -v d="$DOMAIN" 'NF >= 2 && $1 !~ /^#/ && $2 !~ ("\\." d "$") { print $1; exit }' "$TAKEN_HOSTS" 2>/dev/null || true)
if [ -n "$taken" ]; then
  # owner-app's own refusal, which also proves the sudo rule lets the lane reach it
  expect "'$taken', which something else on this box has, cannot be set up here" "not one of the solhann apps" \
    "$(lane "provision $taken")"
  expect "'$taken' takes no server code from the deploy key" "not one of the solhann apps" \
    "$(lane "pb-rsync --server -logDtprce.iLsfxCIvu --delete . $taken/")"
fi
mine=""
while read -r s h _; do
  [ "$h" = "$s.$DOMAIN" ] && [ -f "$ETC/$s.env" ] && { mine=$s; break; }
done < "$APPS"
if [ -n "$mine" ]; then
  expect "$mine is recognised as set up" "already set up" "$(lane "provision $mine")"
  # Its server code gets through owner-lane, pb-deploy-jail and rrsync to rsync itself.
  # With nothing on stdin the rsync server sees only the stream end ("connection
  # unexpectedly closed", code 12) and writes nothing; a refusal says denied or rrsync error.
  expect "$mine's server code reaches its jail" "connection unexpectedly closed" \
    "$(lane "pb-rsync --server -logDtprce.iLsfxCIvu . $mine/")"
else
  echo "  ✗ $APPS lists no app with a PocketBase"; fail=$((fail + 1))
fi
# Wiring only: with no app named, owner-env stops at its usage line and touches nothing.
# (What it refuses and what it writes is kit/tests/test-server.sh's job, not prod's.)
expect "sol may run owner-env, as push-secrets does" "usage: owner-env" \
  "$(sudo -u sol sudo -n /usr/local/bin/owner-env </dev/null 2>&1 || true)"
echo "$pass passed, $fail failed"
[ "$fail" = 0 ] || die "a check failed; to undo: sudo bash $0 --rollback"
echo "✓ done: these apps are set up, deployed and given their secrets by the scripts in"
echo "  /usr/local/bin/owner-*, which go by $CONFDIR. What they replaced is in $BK"
