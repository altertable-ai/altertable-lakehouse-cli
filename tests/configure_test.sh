#!/usr/bin/env bash
# Offline tests for `altertable configure`. No network, no real keychain.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
CLI="${SCRIPT_DIR}/../bin/altertable"

TEST_HOME="$(mktemp -d)"
export ALTERTABLE_CONFIG_HOME="${TEST_HOME}"
export ALTERTABLE_SECRET_BACKEND=file
unset ALTERTABLE_LAKEHOUSE_USERNAME ALTERTABLE_LAKEHOUSE_PASSWORD \
      ALTERTABLE_BASIC_AUTH_TOKEN ALTERTABLE_API_BASE 2>/dev/null || true

cleanup() { rm -rf "${TEST_HOME}"; }
trap cleanup EXIT

file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

CONFIG_FILE="${TEST_HOME}/config"
CRED_FILE="${TEST_HOME}/credentials"

# A fake `curl` placed first on PATH: logs the Authorization header, returns 200.
setup_curl_mock() {
  _CURL_MOCK_DIR="$(mktemp -d)"
  export _CURL_MOCK_AUTH_LOG="${_CURL_MOCK_DIR}/auth.log"
  : > "${_CURL_MOCK_AUTH_LOG}"
  cat > "${_CURL_MOCK_DIR}/curl" <<'MOCK'
#!/usr/bin/env bash
out=""; prev=""
for arg in "$@"; do
  case "$prev" in
    -H) case "$arg" in Authorization:*) printf '%s\n' "$arg" > "${_CURL_MOCK_AUTH_LOG}" ;; esac ;;
    -o) out="$arg" ;;
  esac
  prev="$arg"
done
[[ -n "$out" ]] && printf '{"ok":true}' > "$out"
printf '200'
MOCK
  chmod +x "${_CURL_MOCK_DIR}/curl"
  _CURL_MOCK_SAVED_PATH="${PATH}"
  export PATH="${_CURL_MOCK_DIR}:${PATH}"
}
teardown_curl_mock() {
  export PATH="${_CURL_MOCK_SAVED_PATH}"
  rm -rf "${_CURL_MOCK_DIR}"
}

# ── Lakehouse credential (user/password) ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --user u_blabla --password s_llll >/dev/null 2>&1
grep -q '^user=u_blabla$' "${CONFIG_FILE}" || fail "configure: expected user=u_blabla in config"
grep -q '^lakehouse/password=s_llll$' "${CRED_FILE}" || fail "configure: expected lakehouse/password in credentials"
[[ "$(file_mode "${CRED_FILE}")" == "600" ]] || fail "configure: credentials must be mode 600, got $(file_mode "${CRED_FILE}")"
pass "configure stores lakehouse user/password (credentials chmod 600)"

# ── Basic token ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --basic-token dG9rZW4= >/dev/null 2>&1
grep -q '^lakehouse/basic-token=dG9rZW4=$' "${CRED_FILE}" || fail "configure: expected basic-token in credentials"
pass "configure stores a Basic token"

# ── Management API key (per --env) ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --api-key atm_prod --env production >/dev/null 2>&1
grep -q '^api-key=atm_prod$' "${CRED_FILE}" || fail "configure: expected api-key in credentials"
grep -q '^api_key_env=production$' "${CONFIG_FILE}" || fail "configure: expected api_key_env=production in config"
pass "configure stores an API key with its environment"

# ── Override: a new configure replaces the previous mechanism ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --user u1 --password p1 >/dev/null 2>&1
"${CLI}" configure --api-key atm_x --env prod >/dev/null 2>&1
if grep -q '^lakehouse/password=' "${CRED_FILE}"; then fail "override: previous password should be gone"; fi
if grep -q '^user=' "${CONFIG_FILE}"; then fail "override: previous user should be cleared"; fi
grep -q '^api-key=atm_x$' "${CRED_FILE}" || fail "override: api-key should be stored"
pass "a new configure overrides the previous credential (no cumulation)"

# ── Single-mechanism validation ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
if "${CLI}" configure --user u --password p --api-key k --env e >/dev/null 2>&1; then
  fail "should reject combining mechanisms"
fi
pass "configure rejects combining authentication mechanisms"
if "${CLI}" configure --user u --password p --env prod >/dev/null 2>&1; then
  fail "--env without --api-key should error"
fi
pass "--env is rejected without --api-key"
if "${CLI}" configure --api-key k >/dev/null 2>&1; then
  fail "--api-key without --env should error (bashly needs)"
fi
pass "--api-key without --env is rejected"
if "${CLI}" configure --user u >/dev/null 2>&1; then
  fail "--user without --password should error"
fi
pass "--user without --password is rejected"

# ── stdin secrets ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
printf 's_fromstdin' | "${CLI}" configure --user alice --password-stdin >/dev/null 2>&1
grep -q '^lakehouse/password=s_fromstdin$' "${CRED_FILE}" || fail "--password-stdin should store the piped password"
pass "--password-stdin reads the password from stdin"
printf 'atm_fromstdin' | "${CLI}" configure --api-key-stdin --env prod >/dev/null 2>&1
grep -q '^api-key=atm_fromstdin$' "${CRED_FILE}" || fail "--api-key-stdin should store the piped key"
pass "--api-key-stdin reads the API key from stdin"

# ── configure --list ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --user u_blabla --password s_llll >/dev/null 2>&1
OUT="$("${CLI}" configure --list 2>/dev/null)"
echo "${OUT}" | grep -q 'u_blabla' || fail "--list: should show the username"
echo "${OUT}" | grep -Eq 'password:[[:space:]]*set' || fail "--list: should show password as set"
if echo "${OUT}" | grep -q 's_llll'; then fail "--list: must NOT print the secret value"; fi
echo "${OUT}" | grep -Fq "${CRED_FILE}" || fail "--list: should show the credentials file path as the secret store"
"${CLI}" configure --list >/dev/null 2>&1 || fail "--list: should exit 0"
pass "--list shows the stored mechanism, masks secrets, names the secret store, exits 0"

# ── configure --remove ──
"${CLI}" configure --remove --yes >/dev/null 2>&1
OUT="$("${CLI}" configure --list 2>/dev/null)"
echo "${OUT}" | grep -q 'No credentials configured' || fail "--remove should clear the stored credential"
pass "--remove wipes the stored credential"

# ── interactive ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
printf 'alice\nsecret\n' | "${CLI}" configure >/dev/null 2>&1
grep -q '^user=alice$' "${CONFIG_FILE}" || fail "interactive: should store the username"
grep -q '^lakehouse/password=secret$' "${CRED_FILE}" || fail "interactive: should store the password"
pass "interactive configure stores lakehouse credentials"

# ── stored credentials drive authentication (mock curl) ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --user alice --password secret >/dev/null 2>&1
setup_curl_mock
"${CLI}" query --statement "SELECT 1" >/dev/null 2>&1
AUTH="$(cat "${_CURL_MOCK_AUTH_LOG}")"
EXPECTED="Authorization: Basic $(printf '%s' 'alice:secret' | base64 | tr -d '\n')"
[[ "${AUTH}" == "${EXPECTED}" ]] || fail "auth: expected stored-cred Basic header, got '${AUTH}'"
teardown_curl_mock
pass "commands authenticate with stored lakehouse credentials"

setup_curl_mock
ALTERTABLE_LAKEHOUSE_USERNAME=envuser ALTERTABLE_LAKEHOUSE_PASSWORD=envpass \
  "${CLI}" query --statement "SELECT 1" >/dev/null 2>&1
AUTH="$(cat "${_CURL_MOCK_AUTH_LOG}")"
EXPECTED="Authorization: Basic $(printf '%s' 'envuser:envpass' | base64 | tr -d '\n')"
[[ "${AUTH}" == "${EXPECTED}" ]] || fail "auth: env vars should beat stored creds, got '${AUTH}'"
teardown_curl_mock
pass "environment variables take precedence over stored credentials"

# ── refuse to read a credentials file with permissions looser than 600 ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --user u --password p >/dev/null 2>&1
chmod 644 "${CRED_FILE}"
ERR="$("${CLI}" configure --list 2>&1 >/dev/null)" && fail "--list should refuse a 644 credentials file"
echo "${ERR}" | grep -q 'too open' || fail "expected a 'too open' error, got '${ERR}'"
pass "--list refuses a credentials file looser than 600"
setup_curl_mock
if "${CLI}" query --statement "SELECT 1" >/dev/null 2>&1; then fail "query should refuse a 644 credentials file"; fi
teardown_curl_mock
pass "commands refuse to use a credentials file looser than 600"
chmod 600 "${CRED_FILE}"
"${CLI}" configure --list >/dev/null 2>&1 || fail "--list should accept a 600 credentials file"
pass "a 600 credentials file is accepted"

echo ""
echo -e "${GREEN}All configure tests passed.${NC}"
