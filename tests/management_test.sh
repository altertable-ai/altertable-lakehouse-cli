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

# ── ALTERTABLE_API_KEY overrides the stored key; ALTERTABLE_MANAGEMENT_API_BASE overrides base ──
setup_mgmt_curl_mock
ALTERTABLE_API_KEY=atm_env ALTERTABLE_MANAGEMENT_API_BASE=http://localhost:9/rest/v1 \
  "${CLI}" whoami >/dev/null 2>&1
grep -q '^AUTH=Authorization: Bearer atm_env$' "${_M_LOG}" || fail "mgmt: ALTERTABLE_API_KEY should win"
grep -q '^URL=http://localhost:9/rest/v1/whoami$' "${_M_LOG}" || fail "mgmt: ALTERTABLE_MANAGEMENT_API_BASE should win"
teardown_mgmt_curl_mock
pass "ALTERTABLE_API_KEY and ALTERTABLE_MANAGEMENT_API_BASE take precedence"

# ── no api-key configured → clear error ──
"${CLI}" configure --clear >/dev/null 2>&1
ERR="$(ALTERTABLE_SECRET_BACKEND=file "${CLI}" whoami 2>&1 >/dev/null)"
echo "${ERR}" | grep -q "No management API key" || fail "mgmt: expected 'No management API key' error, got '${ERR}'"
pass "missing management API key errors clearly"

echo ""
echo -e "${GREEN}All management tests passed.${NC}"
