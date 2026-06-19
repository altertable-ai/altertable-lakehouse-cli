#!/usr/bin/env bash
# Offline tests for the management API helpers (whoami / catalogs share these).
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
CLI="${SCRIPT_DIR}/../bin/altertable"

TEST_HOME="$(mktemp -d)"
export ALTERTABLE_CONFIG_HOME="${TEST_HOME}"
export ALTERTABLE_SECRET_BACKEND=file
unset ALTERTABLE_API_KEY ALTERTABLE_ENV ALTERTABLE_MANAGEMENT_API_BASE 2>/dev/null || true
cleanup() { rm -rf "${TEST_HOME}"; }
trap cleanup EXIT

# A fake curl recording method, URL, Authorization header and -d payload to a log,
# returning a canned 200 JSON body. Per-path canned bodies are keyed off the URL.
setup_mgmt_curl_mock() {
  _M_DIR="$(mktemp -d)"
  export _M_LOG="${_M_DIR}/req.log"
  : > "${_M_LOG}"
  cat > "${_M_DIR}/curl" <<'MOCK'
#!/usr/bin/env bash
method=""; url=""; auth=""; payload=""; out=""; prev=""
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
{ printf 'METHOD=%s\n' "$method"; printf 'URL=%s\n' "$url"; printf 'AUTH=%s\n' "$auth"; printf 'PAYLOAD=%s\n' "$payload"; } >> "${_M_LOG}"
[[ -n "$out" ]] && printf '{"principal":{"type":"User","name":"Jane","email":"j@x.io"},"organization":{"name":"Acme","slug":"acme"}}' > "$out"
printf '200'
MOCK
  chmod +x "${_M_DIR}/curl"
  _M_SAVED_PATH="${PATH}"
  export PATH="${_M_DIR}:${PATH}"
}
teardown_mgmt_curl_mock() { export PATH="${_M_SAVED_PATH}"; rm -rf "${_M_DIR}"; }

# ── Bearer auth from stored api-key, default base URL ──
"${CLI}" configure --api-key atm_stored --env production >/dev/null 2>&1
setup_mgmt_curl_mock
"${CLI}" whoami >/dev/null 2>&1
grep -q '^AUTH=Authorization: Bearer atm_stored$' "${_M_LOG}" || fail "mgmt: expected Bearer atm_stored, got '$(grep '^AUTH=' "${_M_LOG}")'"
grep -q '^URL=https://app.altertable.ai/rest/v1/whoami$' "${_M_LOG}" || fail "mgmt: expected default base /whoami URL, got '$(grep '^URL=' "${_M_LOG}")'"
teardown_mgmt_curl_mock
pass "management auth uses stored Bearer api-key against the default base URL"

# ── ALTERTABLE_API_KEY overrides the stored key; ALTERTABLE_MANAGEMENT_API_BASE (a root) overrides base ──
setup_mgmt_curl_mock
ALTERTABLE_API_KEY=atm_env ALTERTABLE_MANAGEMENT_API_BASE=http://localhost:9 \
  "${CLI}" whoami >/dev/null 2>&1
grep -q '^AUTH=Authorization: Bearer atm_env$' "${_M_LOG}" || fail "mgmt: ALTERTABLE_API_KEY should win"
grep -q '^URL=http://localhost:9/rest/v1/whoami$' "${_M_LOG}" || fail "mgmt: expected root + /rest/v1, got '$(grep '^URL=' "${_M_LOG}")'"
teardown_mgmt_curl_mock
pass "ALTERTABLE_MANAGEMENT_API_BASE is a root; the CLI appends /rest/v1"

# ── stored management_api_base (a root) is used when no env var is set ──
printf 'management_api_base=http://localhost:7\n' >> "${ALTERTABLE_CONFIG_HOME}/config"
setup_mgmt_curl_mock
ALTERTABLE_API_KEY=atm_env "${CLI}" whoami >/dev/null 2>&1
grep -q '^URL=http://localhost:7/rest/v1/whoami$' "${_M_LOG}" || fail "mgmt: stored root should be used, got '$(grep '^URL=' "${_M_LOG}")'"
teardown_mgmt_curl_mock
pass "a stored management_api_base root is honored"

# ── a trailing slash on the root is trimmed ──
setup_mgmt_curl_mock
ALTERTABLE_API_KEY=atm_env ALTERTABLE_MANAGEMENT_API_BASE=http://localhost:8/ \
  "${CLI}" whoami >/dev/null 2>&1
grep -q '^URL=http://localhost:8/rest/v1/whoami$' "${_M_LOG}" || fail "mgmt: trailing slash should be trimmed, got '$(grep '^URL=' "${_M_LOG}")'"
teardown_mgmt_curl_mock
pass "a trailing slash on the control-plane root is trimmed"

# A fake curl returning a configurable status (_MOCK_STATUS) and body (_MOCK_BODY).
setup_status_mock() {
  _S_DIR="$(mktemp -d)"
  cat > "${_S_DIR}/curl" <<'MOCK'
#!/usr/bin/env bash
out=""; prev=""
for arg in "$@"; do case "$prev" in -o) out="$arg";; esac; prev="$arg"; done
[[ -n "$out" ]] && printf '%s' "${_MOCK_BODY}" > "$out"
printf '%s' "${_MOCK_STATUS}"
MOCK
  chmod +x "${_S_DIR}/curl"
  _S_SAVED_PATH="${PATH}"
  export PATH="${_S_DIR}:${PATH}"
}
teardown_status_mock() { export PATH="${_S_SAVED_PATH}"; rm -rf "${_S_DIR}"; }

# Need a configured key for these (whoami reaches the request stage).
"${CLI}" configure --api-key atm_stored --env production >/dev/null 2>&1

# ── 500 with an HTML body: friendly message, HTML never leaked ──
setup_status_mock
ERR="$(_MOCK_STATUS=500 _MOCK_BODY='<html><body>Internal Server Error</body></html>' "${CLI}" whoami 2>&1 >/dev/null)"
teardown_status_mock
echo "${ERR}" | grep -q "Server error (500)" || fail "500: expected friendly server error, got '${ERR}'"
echo "${ERR}" | grep -q "<html>" && fail "500: HTML body must not be displayed, got '${ERR}'"
pass "a 5xx HTML error page shows a friendly message and never leaks the HTML"

# ── 401 with a JSON body: friendly message + extracted message ──
setup_status_mock
ERR="$(_MOCK_STATUS=401 _MOCK_BODY='{"error":{"message":"invalid api key"}}' "${CLI}" whoami 2>&1 >/dev/null)"
teardown_status_mock
echo "${ERR}" | grep -q "Authentication failed (401)" || fail "401: expected auth-failed message, got '${ERR}'"
echo "${ERR}" | grep -q "invalid api key" || fail "401: expected extracted JSON message, got '${ERR}'"
pass "a 401 shows an authentication message and the JSON error detail"

# ── 404 with a JSON body lacking a message: friendly message, no HTML leak ──
setup_status_mock
ERR="$(_MOCK_STATUS=404 _MOCK_BODY='{"error":{"code":"not_found"}}' "${CLI}" whoami 2>&1 >/dev/null)"
teardown_status_mock
echo "${ERR}" | grep -q "Not found (404)" || fail "404: expected not-found message, got '${ERR}'"
pass "a 404 shows a not-found message"

# ── no api-key configured → clear error ──
"${CLI}" configure --clear >/dev/null 2>&1
ERR="$("${CLI}" whoami 2>&1 >/dev/null)"
echo "${ERR}" | grep -q "No management API key" || fail "mgmt: expected 'No management API key' error, got '${ERR}'"
pass "missing management API key errors clearly"

echo ""
echo -e "${GREEN}All management tests passed.${NC}"
