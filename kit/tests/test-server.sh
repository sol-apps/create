#!/usr/bin/env bash
# kit/server: install.sh, owner-lane, owner-app, owner-password, owner-env.
#
#   bash kit/tests/test-server.sh
#
# The real scripts run against a throwaway tree. Their absolute paths are rewritten into
# it, and what needs root or the network (useradd, setfacl, chown, systemctl, caddy,
# sudo, visudo, pocketbase, rrsync, pb-deploy-jail, curl) is a stand-in that records what
# it was asked, so this runs anywhere, unprivileged, and touches nothing real.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/kit/server"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1"; fail=$((fail + 1)); }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — got: $2" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — got: $2" ;; *) ok "$1" ;; esac; }
is()    { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 — got: $2"; fi; }

B="$T/usr/local/bin"; S="$T/stubs"; L="$T/log"; STAGE="$T/stage"
mkdir -p "$B" "$S" "$L" "$STAGE" "$T/etc/neighbour" "$T/etc/pocketbase" "$T/etc/caddy/apps" \
  "$T/etc/forge" "$T/etc/sudoers.d" "$T/var/lib/pocketbase" "$T/var/www/apps" "$T/home/sol/.ssh"

# Every absolute path moved into the tree; the neighbour's files get neutral names.
rewrite() {
  sed -e "s#/etc/solhann#$T/etc/solhann#g" -e "s#/etc/pocketbase#$T/etc/pocketbase#g" \
      -e "s#/etc/caddy#$T/etc/caddy#g" -e "s#/etc/sudoers.d#$T/etc/sudoers.d#g" \
      -e "s#/etc/greenlight/hosts#$T/etc/neighbour/hosts#g" -e "s#/etc/forgejo/app.ini#$T/etc/forge/app.ini#g" \
      -e "s#/var/lib/pocketbase#$T/var/lib/pocketbase#g" -e "s#/var/www/apps#$T/var/www/apps#g" \
      -e "s#/var/backups/solhann#$T/var/backups/solhann#g" -e "s#/home/sol#$T/home/sol#g" \
      -e "s#/usr/local/bin/#$B/#g" -e "s#/usr/bin/rrsync#$S/rrsync#g" \
      -e "s#http://127.0.0.1:3000/api/v1#http://forge.test/api/v1#g" \
      -e "s#^\( *\)sleep 1\$#\1sleep 0#" "$1" > "$2"
  chmod +x "$2"
}
for t in install.sh owner-lane owner-app owner-password owner-env adopt-app; do rewrite "$SRC/$t" "$STAGE/$t"; done

stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$S/$1"; chmod +x "$S/$1"; }
stub rrsync         'printf "%s|%s\n" "$*" "$SSH_ORIGINAL_COMMAND" >> "'"$L"'/rrsync"'
stub pocketbase     'printf "%s\n" "$*" >> "'"$L"'/pocketbase"; env | grep -E "^(GREENLIGHT|OIDC)_" >> "'"$L"'/pocketbase.env"; exit 0'
stub id             'if [ "$1" = -u ] && [ -z "${2:-}" ]; then echo 0; elif grep -qx "${2:-}" "'"$T"'/users" 2>/dev/null; then echo 999; else exit 1; fi'
stub useradd        'echo "${@: -1}" >> "'"$T"'/users"'
stub setfacl        ':'
stub chown          ':'
stub visudo         'exit "${VISUDO_RC:-0}"'
# stat -c %a <file>: the mode, as GNU stat prints it.
stub stat           '[ "$1" = -c ] && exec /usr/bin/stat -f %Lp "$3"; exec /usr/bin/stat "$@"'
command -v gstat >/dev/null 2>&1 || /usr/bin/stat -c %a / >/dev/null 2>&1 && rm -f "$S/stat"
stub systemctl      '[ "$1" = cat ] && exit 0; echo "$*" >> "'"$L"'/systemctl"'
stub caddy          'echo "$*" >> "'"$L"'/caddy"; exit "${CADDY_RC:-0}"'
# sudo: drop -n and -u <user>, run the rest as this user.
stub sudo           'while [ "$#" -gt 0 ]; do case "$1" in -n) shift ;; -u) shift 2 ;; *) break ;; esac; done; exec "$@"'
# install: the same, minus ownership.
stub install        'a=(); while [ "$#" -gt 0 ]; do case "$1" in -o|-g) shift 2 ;; *) a+=("$1"); shift ;; esac; done; exec /usr/bin/install "${a[@]}"'
command -v flock >/dev/null 2>&1 || stub flock ':'
# curl: the neighbour's git host, GitHub and the health probe answer from FJ_CODE /
# FJ_MIRROR / GH_CODE / HEALTH.
stub curl '
out=""; fmt=""; url=""
while [ "$#" -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; -w) fmt="$2"; shift 2 ;; -m|-H) shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac; done
case "$url" in
  http://forge.test/*)      code="${FJ_CODE:-404}"; body="{\"mirror\": ${FJ_MIRROR:-false}}" ;;
  https://api.github.com/*) code="${GH_CODE:-200}"; body="{}" ;;
  http://127.0.0.1:*)       [ "${HEALTH:-200}" = 200 ] && exit 0 || exit 22 ;;
  *) exit 6 ;;
esac
[ -n "$out" ] && printf "%s" "$body" > "$out"
[ -n "$fmt" ] && printf "%s" "$code"
exit 0'
# The jail ends as the real one does when the rsync stream is empty.
printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "$*" "$SSH_ORIGINAL_COMMAND" >> "%s/jail"\necho "rsync: connection unexpectedly closed (0 bytes received so far) [Receiver]" >&2\nexit 12\n' "$L" > "$B/pb-deploy-jail"
cp "$S/pocketbase" "$B/pocketbase"; chmod +x "$B/pb-deploy-jail" "$B/pocketbase"
export PATH="$S:$PATH"

# The box before the install: three of our apps with a PocketBase (one carrying settings
# it no longer reads), one static one, and two things that are somebody else's.
cat > "$T/etc/neighbour/hosts" <<EOF
expenses expenses.solhann.net
wizard build.other.example
coin-toss coin-toss.other.example
cymbal cymbal.solhann.net
aba aba.solhann.net
ghost ghost.solhann.net
EOF
: > "$T/etc/forge/app.ini"
printf 'PB_PORT=8101\n' > "$T/etc/pocketbase/expenses.env"
printf 'PB_PORT=8102\nSPOTIFY_ID=abc\nOIDC_ISSUER=https://id.example\nOIDC_CLIENT_ID=x\nGREENLIGHT_IDENTITY_MODE=production\n' > "$T/etc/pocketbase/cymbal.env"
printf 'PB_PORT=8103\nGREENLIGHT_ACCESS_MODE=public\n' > "$T/etc/pocketbase/aba.env"
printf 'PB_PORT=8104\n' > "$T/etc/pocketbase/coin-toss.env"
for s in expenses cymbal aba; do printf '%s.solhann.net {\n}\n' "$s" > "$T/etc/caddy/apps/$s.caddy"; echo "pb-$s" >> "$T/users"; mkdir -p "$T/var/lib/pocketbase/$s"; done
printf 'coin-toss.other.example {\n}\n' > "$T/etc/caddy/apps/coin-toss.caddy"
printf 'old-secret\n' > "$T/etc/pocketbase/owner.superuser"
printf 'command="%s/owner-lane",restrict ssh-ed25519 AAAA deploy\n' "$B" > "$T/home/sol/.ssh/authorized_keys"
printf '#!/bin/sh\necho OLD-LANE\n' > "$B/owner-lane"; printf '#!/bin/sh\necho OLD-APP\n' > "$B/owner-app"; chmod +x "$B/owner-lane" "$B/owner-app"
printf 'old rule\n' > "$T/etc/sudoers.d/owner-lane"

lane() { SSH_ORIGINAL_COMMAND="$1" "$B/owner-lane" </dev/null 2>&1; }
CONF="$T/etc/solhann/conf"; APPS="$T/etc/solhann/apps"

echo "install, first run:"
out=$(bash "$STAGE/install.sh" 2>&1); rc=$?
is "it succeeds" "$rc" 0
has "all its own checks pass" "$out" "0 failed"
has "including that sol can reach owner-env" "$out" "✓ sol may run owner-env"
has "conf names the domain" "$(cat "$CONF")" "DOMAIN=solhann.net"
has "conf points at the neighbour's list of names" "$(cat "$CONF")" "TAKEN_HOSTS=$T/etc/neighbour/hosts"
has "and at the box's git host" "$(cat "$CONF")" "TAKEN_FORGE=http://forge.test/api/v1/repos/sol-apps"
is "apps lists exactly our apps that have a PocketBase" "$(sort "$APPS" | tr '\n' ',')" "aba aba.solhann.net,cymbal cymbal.solhann.net,expenses expenses.solhann.net,"
for t in owner-lane owner-app owner-password owner-env adopt-app; do
  if cmp -s "$STAGE/$t" "$B/$t"; then ok "$t installed"; else bad "$t installed"; fi
done
has "the sudoers rule allows owner-app and owner-env" "$(cat "$T/etc/sudoers.d/owner-lane")" "NOPASSWD: $B/owner-app, $B/owner-env"
BK=$(ls -1d "$T"/var/backups/solhann/server-* | tail -1)
has "the old owner-lane is kept" "$(cat "$BK/owner-lane")" "OLD-LANE"
has "the old sudoers rule is kept" "$(cat "$BK/sudoers")" "old rule"
is "cymbal keeps its port and its own secret, and loses the settings nothing reads" "$(tr '\n' ',' < "$T/etc/pocketbase/cymbal.env")" "PB_PORT=8102,SPOTIFY_ID=abc,"
is "aba likewise" "$(tr '\n' ',' < "$T/etc/pocketbase/aba.env")" "PB_PORT=8103,"
has "the removed settings are in the backup" "$(cat "$BK/env/cymbal.env")" "OIDC_ISSUER=https://id.example"
is "somebody else's app is not touched" "$(cat "$T/etc/pocketbase/coin-toss.env")" "PB_PORT=8104"
hasnt "no app is restarted by the install" "$(cat "$L/systemctl" 2>/dev/null)" "restart"

echo "install, again:"
before=$(cat "$CONF" "$APPS" | /sbin/md5 -q 2>/dev/null || cat "$CONF" "$APPS" | md5sum)
out=$(bash "$STAGE/install.sh" 2>&1); rc=$?
is "it succeeds" "$rc" 0
is "conf and apps are left alone" "$(cat "$CONF" "$APPS" | /sbin/md5 -q 2>/dev/null || cat "$CONF" "$APPS" | md5sum)" "$before"
has "nothing is reinstalled" "$out" "= $B/owner-env"

echo "install refuses:"
mv "$T/etc/pocketbase/owner.superuser" "$T/pw"; out=$(bash "$STAGE/install.sh" 2>&1); rc=$?; mv "$T/pw" "$T/etc/pocketbase/owner.superuser"
has "with no shared password" "$rc:$out" "1:✗ no shared /_/ password"
cp "$T/home/sol/.ssh/authorized_keys" "$T/ak"; echo 'ssh-ed25519 AAAA x' > "$T/home/sol/.ssh/authorized_keys"; out=$(bash "$STAGE/install.sh" 2>&1); rc=$?; cp "$T/ak" "$T/home/sol/.ssh/authorized_keys"
has "when the deploy key does not run owner-lane" "$rc:$out" "1:✗ the deploy key does not run owner-lane"

echo "owner-lane:"
has "a site goes to the write-only static lane" "$(lane 'rsync --server -logDtprze.iLsfxCIvu --delete . hello/'; cat "$L/rrsync")" "-wo -munge $T/var/www/apps|rsync --server"
has "interactive use is refused" "$(SSH_ORIGINAL_COMMAND= "$B/owner-lane" 2>&1)" "denied"
has "an unknown verb is refused" "$(lane 'cat /etc/passwd')" "denied: unknown command"
has "our app's server code reaches its own jail" "$(lane 'pb-rsync --server -logDtprce.iLsfxCIvu --delete . cymbal/'; cat "$L/jail")" "cymbal|rsync --server -logDtprce.iLsfxCIvu --delete . cymbal/"
has "somebody else's app takes no server code" "$(lane 'pb-rsync --server -x . coin-toss/')" "is not one of the solhann apps"
has "nor does a name only the neighbour's list calls ours" "$(lane 'pb-rsync --server -x . ghost/')" "is not one of the solhann apps"
has "a path that climbs out is refused" "$(lane 'pb-rsync --server -x . ../etc/')" "denied"
has "a pb-rsync that is not rsync --server is refused" "$(lane 'pb-rsync -e sh cymbal/')" "malformed"
has "provision takes exactly one slug" "$(lane 'provision a b')" "usage"

echo "owner-app:"
has "an app that is set up: nothing to do" "$(lane 'provision expenses')" "already set up"
has "somebody else's app is refused" "$(lane 'provision coin-toss')" "not one of the solhann apps"
has "a name the neighbour's list has elsewhere is refused" "$(lane 'provision wizard')" "served at build.other.example"
has "a name the box's git host holds is refused" "$(FJ_CODE=200 FJ_MIRROR=false lane 'provision newapp')" "taken on this box's git host"
has "an unreachable git host refuses rather than guesses" "$(FJ_CODE=500 lane 'provision newapp')" "cannot ask"
has "a name with no public repository is refused" "$(GH_CODE=404 lane 'provision newapp')" "not a public repository"
: > "$L/pocketbase"; : > "$L/pocketbase.env"; : > "$L/systemctl"
out=$(FJ_CODE=200 FJ_MIRROR=true lane 'provision newapp')
has "a new app is set up (a mirror on the git host is no claim)" "$out" "✓ newapp: PocketBase on 127.0.0.1:8105"
has "it gets the next free port" "$(cat "$T/etc/pocketbase/newapp.env")" "PB_PORT=8105"
has "its own user" "$(cat "$T/users")" "pb-newapp"
has "the shared password, as admin@solhann.net" "$(cat "$L/pocketbase")" "superuser upsert admin@solhann.net old-secret"
is "no leftover settings are handed to PocketBase" "$(cat "$L/pocketbase.env")" ""
has "its service and migrations watcher are started" "$(tr '\n' ' ' < "$L/systemctl")" "enable --now --quiet pocketbase@newapp enable --now --quiet pb-migrate@newapp.path"
has "a Caddy block for its address" "$(cat "$T/etc/caddy/apps/newapp.caddy")" "newapp.solhann.net {"
has "it is recorded in our list" "$(cat "$APPS")" "newapp newapp.solhann.net"
hasnt "and not in the neighbour's" "$(cat "$T/etc/neighbour/hosts")" "newapp"
has "its server code is now accepted" "$(lane 'pb-rsync --server -x . newapp/'; tail -1 "$L/jail")" "newapp|rsync --server -x . newapp/"
out=$(HEALTH=500 lane 'provision sickapp')
has "an app that does not come up is not published" "$out" "did not come up"
[ -f "$T/etc/caddy/apps/sickapp.caddy" ] && bad "no Caddy block for it" || ok "no Caddy block for it"
has "and the next run resumes it" "$(lane 'provision sickapp')" "✓ sickapp: PocketBase"

echo "owner-env:"
envf="$T/etc/pocketbase/cymbal.env"; : > "$L/systemctl"
out=$(printf 'SPOTIFY_ID=new\nTOKEN_KEY=a=b=c\n\n' | "$B/owner-env" cymbal 2>&1); rc=$?
has "new secrets replace the old" "$rc:$out" "0:✓ cymbal: 2 runtime secret(s) applied"
is "the port is kept, values with = survive, blank lines are skipped" "$(tr '\n' ',' < "$envf")" "PB_PORT=8102,SPOTIFY_ID=new,TOKEN_KEY=a=b=c,"
has "the app is restarted" "$(cat "$L/systemctl")" "try-restart pocketbase@cymbal"
hasnt "the secrets are not printed back" "$out" "a=b=c"
[ -e "$envf.prev" ] && bad "no copy of the old file is left behind" || ok "no copy of the old file is left behind"
keep=$(cat "$envf")
has "nothing on stdin changes nothing" "$("$B/owner-env" cymbal </dev/null 2>&1)" "nothing on stdin"
has "PB_PORT cannot be set" "$(printf 'PB_PORT=9\n' | "$B/owner-env" cymbal 2>&1)" "PB_PORT is this box's"
has "a lower-case key is refused" "$(printf 'A=1\nbad_key=2\n' | "$B/owner-env" cymbal 2>&1)" "bad key 'bad_key'"
has "a line with no = is refused" "$(printf 'JUSTAWORD\n' | "$B/owner-env" cymbal 2>&1)" "not KEY=value"
is "and the file is as it was after all four" "$(cat "$envf")" "$keep"
out=$(printf 'X=1\n' | HEALTH=500 "$B/owner-env" cymbal 2>&1); rc=$?
has "an app that does not come back gets its old secrets back" "$rc:$out" "1:✗ owner-env: cymbal did not come back healthy"
is "the file is restored" "$(cat "$envf")" "$keep"
has "somebody else's app is refused" "$(printf 'X=1\n' | "$B/owner-env" coin-toss 2>&1)" "not one of the solhann apps"
is "and untouched" "$(cat "$T/etc/pocketbase/coin-toss.env")" "PB_PORT=8104"
out=$("$B/owner-env" cymbal --clear 2>&1)
is "--clear leaves only the port" "$(tr '\n' ',' < "$envf")" "PB_PORT=8102,"

echo "owner-password --apply:"
: > "$L/pocketbase"
out=$("$B/owner-password" --apply 2>&1); rc=$?
has "it applies to our apps" "$rc:$out" "app(s) take admin@solhann.net"
has "each one" "$(cat "$L/pocketbase")" "--dir $T/var/lib/pocketbase/aba/pb_data"
hasnt "and to nobody else's" "$(cat "$L/pocketbase")" "coin-toss"

echo "adopt-app:"
# An app somebody else runs on this box, about to become ours: served at another
# address, in the neighbour's list, with settings of theirs in its environment, and its
# future name already answered by a "retired" block in another Caddy file.
printf 'PB_PORT=8110\nGREENLIGHT_ACCESS_MODE=public\nKEEP_ME=1\n' > "$T/etc/pocketbase/board.env"
printf 'board.other.example {\n\theader {\n\t\t?Content-Security-Policy "frame-ancestors x"\n\t}\n\treverse_proxy 127.0.0.1:8110\n}\n' > "$T/etc/caddy/apps/board.caddy"
printf 'theirs-only\n' > "$T/etc/pocketbase/board.superuser"
echo "pb-board" >> "$T/users"; mkdir -p "$T/var/lib/pocketbase/board"
echo "board board.other.example" >> "$T/etc/neighbour/hosts"
cat > "$T/etc/caddy/retired.caddy" <<'EOF'
before.solhann.net {
	respond "Gone" 410
}
board.solhann.net {
	tls {
		dns cloudflare {env.CF_API_TOKEN}
	}
	respond "Gone" 410
}
after.solhann.net {
	respond "Gone" 410
}
EOF
snap() { cat "$T/etc/caddy/apps/board.caddy" "$T/etc/caddy/retired.caddy" "$T/etc/neighbour/hosts" "$T/etc/pocketbase/board.env" "$T/etc/pocketbase/board.superuser" "$APPS" | cksum; }
orig=$(snap)
has "it will not take somebody else's app from the deploy lane first" "$(lane 'provision board')" "not one of the solhann apps"
has "the address it is served at must be named" "$("$B/adopt-app" board --from wrong.other.example 2>&1)" "is served at board.other.example, not wrong.other.example"
has "an app that is down is not adopted" "$(HEALTH=500 "$B/adopt-app" board --from board.other.example 2>&1)" "is not answering"
has "an app with no PocketBase here is not adopted" "$("$B/adopt-app" nosuch --from nosuch.other.example 2>&1)" "has no PocketBase on this box"
out=$(CADDY_RC=1 "$B/adopt-app" board --from board.other.example 2>&1); rc=$?
has "a Caddy config that does not validate stops it" "$rc:$out" "did not validate"
is "and every file is as it was" "$(snap)" "$orig"
: > "$L/systemctl"; : > "$L/pocketbase"
out=$("$B/adopt-app" board --from board.other.example 2>&1); rc=$?
has "it is adopted" "$rc:$out" "✓ board is one of the solhann apps: https://board.solhann.net"
cf=$(cat "$T/etc/caddy/apps/board.caddy")
is "its Caddy block serves the new address first" "$(printf '%s\n' "$cf" | head -1)" "board.solhann.net {"
has "on the same port" "$cf" "reverse_proxy 127.0.0.1:8110"
has "the old address redirects, path and all" "$cf" "redir https://board.solhann.net{uri} permanent"
hasnt "the previous owner's header is gone" "$cf" "frame-ancestors"
ret=$(cat "$T/etc/caddy/retired.caddy")
hasnt "the block that answered for the new name is gone" "$ret" "board.solhann.net"
has "the block before it is kept" "$ret" "before.solhann.net {"
has "and the one after it" "$ret" "after.solhann.net {"
is "exactly its lines were removed" "$(printf '%s\n' "$ret" | grep -c .)" "6"
has "Caddy is reloaded" "$(cat "$L/systemctl")" "reload caddy"
has "it is in our list" "$(cat "$APPS")" "board board.solhann.net"
hasnt "and out of the neighbour's" "$(cat "$T/etc/neighbour/hosts")" "board"
has "the neighbour's other lines are untouched" "$(cat "$T/etc/neighbour/hosts")" "coin-toss coin-toss.other.example"
is "its port and its own settings stay; the previous owner's go" "$(tr '\n' ',' < "$T/etc/pocketbase/board.env")" "PB_PORT=8110,KEEP_ME=1,"
has "it takes the shared password" "$(cat "$L/pocketbase")" "superuser upsert admin@solhann.net old-secret --dir $T/var/lib/pocketbase/board/pb_data"
hasnt "it is never restarted" "$(cat "$L/systemctl")" "restart"
has "the deploy lane now knows it" "$(lane 'provision board')" "already set up"
has "and takes its server code" "$(lane 'pb-rsync --server -x . board/'; tail -1 "$L/jail")" "board|rsync --server -x . board/"
has "a second run has nothing to do" "$("$B/adopt-app" board --from board.other.example 2>&1)" "already one of the solhann apps"
out=$("$B/adopt-app" board --rollback 2>&1); rc=$?
has "rollback succeeds" "$rc:$out" "✓ board is as it was"
is "and every file is as it was, our list included" "$(snap)" "$orig"
has "with its own password back" "$(tail -1 "$L/pocketbase")" "superuser upsert admin@solhann.net theirs-only"

echo "rollback:"
out=$(bash "$STAGE/install.sh" --rollback 2>&1); rc=$?
is "it succeeds" "$rc" 0
LAST=$(ls -1d "$T"/var/backups/solhann/server-* | tail -1)
if cmp -s "$LAST/owner-lane" "$B/owner-lane"; then ok "owner-lane is the one in the latest backup"; else bad "owner-lane is the one in the latest backup"; fi
[ -f "$CONF" ] && ok "/etc/solhann is left in place" || bad "/etc/solhann is left in place"

echo "the scripts themselves:"
if grep -rIqiE 'greenlight|greenlit' "$SRC/owner-lane" "$SRC/owner-app" "$SRC/owner-password" "$SRC/owner-env"; then
  bad "the four everyday scripts name no other system"
else ok "the four everyday scripts name no other system"; fi
is "install.sh names the neighbour's files in one place only" "$(grep -cE '^NEIGHBOUR_' "$SRC/install.sh")" "3"

echo
echo "  passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
