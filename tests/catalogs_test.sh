#!/usr/bin/env bash
# Offline tests for `altertable catalogs` (create + list).
set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
CLI="${SCRIPT_DIR}/../bin/altertable"

TEST_HOME="$(mktemp -d)"
export ALTERTABLE_CONFIG_HOME="${TEST_HOME}"
export ALTERTABLE_SECRET_BACKEND=file
export ALTERTABLE_API_KEY=atm_test
export ALTERTABLE_ENV=production
unset ALTERTABLE_MANAGEMENT_API_BASE 2>/dev/null || true
cleanup() { rm -rf "${TEST_HOME}"; }
trap cleanup EXIT

# Fake curl: logs METHOD/URL/AUTH/PAYLOAD per call; returns a per-path canned body.
# A database response is returned for .../databases, connections for .../connections.
setup_cat_mock() {
  _C="$(mktemp -d)"; export _C_LOG="${_C}/req.log"; : > "${_C_LOG}"
  cat > "${_C}/curl" <<'MOCK'
#!/usr/bin/env bash
method="GET"; url=""; auth=""; payload=""; out=""; prev=""
for arg in "$@"; do
  case "$prev" in
    -X) method="$arg" ;;
    -H) case "$arg" in Authorization:*) auth="$arg" ;; esac ;;
    -d) payload="$arg" ;;
    -o) out="$arg" ;;
  esac
  case "$arg" in http*://*) url="$arg" ;; esac
  prev="$arg"
done
{ printf 'METHOD=%s\n' "$method"; printf 'URL=%s\n' "$url"; printf 'AUTH=%s\n' "$auth"; printf 'PAYLOAD=%s\n' "$payload"; printf -- '---\n'; } >> "${_C_LOG}"
body='{}'
case "$url" in
  *"/databases")
    if [[ "$method" == "POST" ]]; then
      body='{"database":{"name":"My Cat","slug":"my-cat","engine":"altertable","catalog":"my_cat"}}'
    else
      body='{"databases":[{"name":"My Cat","slug":"my-cat","engine":"altertable","catalog":"my_cat"}]}'
    fi ;;
  *"/connections") body='{"connections":[{"name":"Prod PG","slug":"prod-pg","engine":"postgres","catalog":"prod_pg"}]}';;
esac
[[ -n "$out" ]] && printf '%s' "$body" > "$out"
printf '200'
MOCK
  chmod +x "${_C}/curl"; _CSP="${PATH}"; export PATH="${_C}:${PATH}"
}
teardown_cat_mock() { export PATH="${_CSP}"; rm -rf "${_C}"; }

# ── create: engine validation ──
ERR="$("${CLI}" catalogs create --engine postgres --name "X" 2>&1 >/dev/null)"
echo "${ERR}" | grep -Fq "Only the 'altertable' engine is supported" || fail "create: expected engine rejection, got '${ERR}'"
pass "catalogs create rejects non-altertable engines"

# ── create: request shape ──
setup_cat_mock
OUT="$("${CLI}" catalogs create --engine altertable --name "My Cat" 2>/dev/null)"
grep -q '^METHOD=POST$' "${_C_LOG}" || fail "create: expected POST"
grep -q '^URL=https://app.altertable.ai/rest/v1/environments/production/databases$' "${_C_LOG}" || fail "create: wrong URL: $(grep '^URL=' "${_C_LOG}")"
grep -q '^AUTH=Authorization: Bearer atm_test$' "${_C_LOG}" || fail "create: wrong auth"
PAYLOAD="$(grep '^PAYLOAD=' "${_C_LOG}" | sed 's/^PAYLOAD=//')"
[[ "$(printf '%s' "$PAYLOAD" | jq -cS '.')" == '{"engine":"altertable","name":"My Cat"}' ]] || fail "create: wrong payload: '${PAYLOAD}'"
teardown_cat_mock
echo "${OUT}" | grep -Fq 'Created catalog "My Cat"' || fail "create: missing confirmation: '${OUT}'"
pass "catalogs create posts to /databases with the right payload and confirms"

# ── create: requires an environment ──
ERR="$(ALTERTABLE_ENV='' "${CLI}" catalogs create --engine altertable --name "X" 2>&1 >/dev/null)"
echo "${ERR}" | grep -Fq "No environment set" || fail "create: expected env-required error, got '${ERR}'"
pass "catalogs create requires an environment"

# ── list: calls databases then connections, databases first in the table ──
setup_cat_mock
OUT="$("${CLI}" catalogs list 2>/dev/null)"
# Both endpoints were called, databases before connections.
DB_URL_LINE="$(grep -n '^URL=.*/databases$' "${_C_LOG}" | head -1 | cut -d: -f1)"
CONN_URL_LINE="$(grep -n '^URL=.*/connections$' "${_C_LOG}" | head -1 | cut -d: -f1)"
teardown_cat_mock
[[ -n "$DB_URL_LINE" && -n "$CONN_URL_LINE" ]] || fail "list: expected both /databases and /connections calls"
[[ "$DB_URL_LINE" -lt "$CONN_URL_LINE" ]] || fail "list: /databases must be called before /connections"
# Output: header + database row before connection row.
echo "${OUT}" | grep -Eq '^TYPE[[:space:]]+NAME[[:space:]]+SLUG[[:space:]]+ENGINE[[:space:]]+CATALOG' || fail "list: missing header: '${OUT}'"
DB_OUT_LINE="$(echo "${OUT}" | grep -n 'database' | head -1 | cut -d: -f1)"
CONN_OUT_LINE="$(echo "${OUT}" | grep -n 'connection' | head -1 | cut -d: -f1)"
[[ -n "$DB_OUT_LINE" && -n "$CONN_OUT_LINE" && "$DB_OUT_LINE" -lt "$CONN_OUT_LINE" ]] || fail "list: databases must render before connections: '${OUT}'"
pass "catalogs list shows databases before connections in a table"

# ── list: a non-2xx (e.g. 404 from /databases) hard-fails ──
setup_cat_404() {
  _C="$(mktemp -d)"; _CSP="${PATH}"
  cat > "${_C}/curl" <<'MOCK'
#!/usr/bin/env bash
out=""; prev=""
for arg in "$@"; do case "$prev" in -o) out="$arg";; esac; prev="$arg"; done
[[ -n "$out" ]] && printf '{"error":{"code":"not_found"}}' > "$out"
printf '404'
MOCK
  chmod +x "${_C}/curl"; export PATH="${_C}:${PATH}"
}
setup_cat_404
if "${CLI}" catalogs list >/dev/null 2>&1; then export PATH="${_CSP}"; rm -rf "${_C}"; fail "list: a 404 must hard-fail"; fi
export PATH="${_CSP}"; rm -rf "${_C}"
pass "catalogs list hard-fails on a non-2xx response"

echo ""
echo -e "${GREEN}All catalogs tests passed.${NC}"
