#!/usr/bin/env bash
# create-app's contract, and the kit's own rules.
#
#   bash kit/tests/test-create-app.sh
#
# create-app runs for real in a throwaway folder; `gh`, `curl` and `sleep` are stand-ins
# that record what was asked of them, so no repo is created and nothing is deployed. The
# skill is copied out of the repo first and run with HOME pointing at the throwaway
# folder: it has to work as the installed copy does, with nothing else on the machine.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB="$(mktemp -d)"
trap 'rm -rf "$LAB"' EXIT

pass=0; fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1"; fail=$((fail + 1)); }
check() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi; }
refute() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$label"; else ok "$label"; fi; }

mkdir -p "$LAB/fake-bin" "$LAB/home/.claude/skills" "$LAB/apps"
cp -R "$ROOT/kit/skill/create-app" "$LAB/home/.claude/skills/create-app"
SCRIPT="$LAB/home/.claude/skills/create-app/create-app.sh"
EVENTS="$LAB/events"

cat > "$LAB/fake-bin/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh:%s\n' "$*" >> "$EVENTS"
case "${1:-} ${2:-}" in
  "repo view") exit 1 ;;      # the name is free
  "run list") printf '101\n' ;;
esac
exit 0
SH
printf '#!/usr/bin/env bash\nprintf "curl:%%s\\n" "$*" >> "$EVENTS"\nprintf 200\n' > "$LAB/fake-bin/curl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$LAB/fake-bin/sleep"
chmod +x "$LAB/fake-bin/"*

run_create() { # run_create <args…> — output in $LAB/out, status returned
  : > "$EVENTS"
  env -i HOME="$LAB/home" PATH="$LAB/fake-bin:/usr/bin:/bin" EVENTS="$EVENTS" \
    SOLHANN_PROJECTS="$LAB/apps" GIT_CONFIG_NOSYSTEM=1 \
    bash "$SCRIPT" "$@" > "$LAB/out" 2>&1
}
CALLER='uses: sol-apps/create/.github/workflows/simple.yml@main'

echo "a static app:"
run_create bat-quiz "Bat Quiz" "How well do you know bats & owls?"; rc=$?
A="$LAB/apps/bat-quiz"
check "the script succeeds" [ "$rc" -eq 0 ]
check "index.html carries the title" grep -q "Bat Quiz" "$A/index.html"
check "the README front matter carries the description, & and all" grep -q "How well do you know bats & owls?" "$A/README.md"
check "the deploy caller points at create's workflow" grep -qF "$CALLER" "$A/.github/workflows/deploy.yml"
refute "no PocketBase files" [ -e "$A/pb-auth.js" -o -e "$A/pb_hooks" -o -e "$A/vendor" ]
refute "no spec.json" [ -e "$A/spec.json" ]
check "one commit, on main" [ "$(git -C "$A" rev-list --count main)" = 1 ]
check "the repo is created public and pushed in one step" grep -q '^gh:repo create sol-apps/bat-quiz --public .*--push' "$EVENTS"
check "tagged for the gallery, with its address" grep -q '^gh:repo edit sol-apps/bat-quiz --homepage https://bat-quiz.solhann.net --add-topic solhann-app --add-topic owner-built' "$EVENTS"
check "it waits for the deploy run" grep -q '^gh:run watch --repo sol-apps/bat-quiz 101 --exit-status' "$EVENTS"
check "it checks the live address" grep -q 'curl:.*https://bat-quiz.solhann.net/$' "$EVENTS"
refute "it asks for nothing else of GitHub (protection, environments, secrets)" grep -qE '^gh:(api|secret|workflow)' "$EVENTS"

echo "an app with a database:"
run_create --backend pocketbase bat-log "Bat Log" "Sightings."; rc=$?
B="$LAB/apps/bat-log"
check "the script succeeds" [ "$rc" -eq 0 ]
check "the PocketBase SDK comes from the skill itself" cmp -s "$B/vendor/pocketbase.umd.js" "$ROOT/kit/skill/create-app/template/vendor/pocketbase.umd.js"
check "index.html loads the SDK and pb-auth.js" grep -q 'src="pb-auth.js"' "$B/index.html"
check "hooks and the sign-up-closing migration are there" [ -f "$B/pb_hooks/main.pb.js" -a -f "$B/pb_migrations/1759276800_owner_only_accounts.js" ]
check "local data is gitignored" grep -qxF '.pb_data/' "$B/.gitignore"
check "it checks the backend's health" grep -q 'curl:.*https://bat-log.solhann.net/api/health$' "$EVENTS"
check "it points at push-secrets, not an old command" grep -q 'push-secrets bat-log' "$LAB/out"

echo "what it refuses:"
run_create Bad_Slug "X" "Y"; refute "a slug that is not a hostname" [ "$?" -eq 0 ]
run_create --backend pocketbase "$(printf 'a%.0s' $(seq 1 29))" "X" "Y"; refute "a database app whose name is over 28 characters" [ "$?" -eq 0 ]
run_create --access public some-app "X" "Y"; refute "--access (there are no access modes)" [ "$?" -eq 0 ]
run_create bat-quiz "Again" "Twice"; refute "a folder that already exists" [ "$?" -eq 0 ]
run_create only-two "args"; refute "a missing description" [ "$?" -eq 0 ]

echo "the kit:"
W="$ROOT/.github/workflows/simple.yml"
check "the workflow never publishes kit/" grep -qF -- "--exclude '/kit/'" "$W"
check "nor pb_hooks/ and pb_migrations/" grep -qF -- "--exclude 'pb_hooks/' --exclude 'pb_migrations/'" "$W"
check "create deploys through the workflow beside it" grep -qF 'uses: ./.github/workflows/simple.yml' "$ROOT/.github/workflows/deploy.yml"
check "the template's caller is the one new apps get" grep -qF "$CALLER" "$ROOT/kit/skill/create-app/template/deploy.yml"
for f in "$ROOT"/kit/bin/* "$ROOT"/kit/skill/install-skill.sh "$ROOT"/kit/skill/create-app/create-app.sh "$ROOT"/kit/server/*; do
  check "$(basename "$f") parses" bash -n "$f"
done
refute "nothing in the skill, the tools or the workflow needs another checkout" \
  grep -rIqiE 'greenlight|greenlit|SOLHANN_CONTROL_PLANE|sol-apps/workflows' \
    "$ROOT/kit/skill" "$ROOT/kit/bin" "$ROOT/kit/README.md" "$ROOT/.github"

echo
echo "  passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
