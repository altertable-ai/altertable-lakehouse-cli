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
      ALTERTABLE_BASIC_AUTH_TOKEN ALTERTABLE_API_KEY ALTERTABLE_ENV \
      ALTERTABLE_API_BASE ALTERTABLE_APP_BASE 2>/dev/null || true

cleanup() { rm -rf "${TEST_HOME}"; }
trap cleanup EXIT

file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

CONFIG_FILE="${TEST_HOME}/config"
CRED_FILE="${TEST_HOME}/credentials"

# ── Task 1: lakehouse credential storage ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --user u_blabla --password s_llll >/dev/null 2>&1
grep -q '^user=u_blabla$' "${CONFIG_FILE}" || fail "configure: expected user=u_blabla in config"
pass "configure stores lakehouse username in config"
grep -q '^lakehouse/password=s_llll$' "${CRED_FILE}" || fail "configure: expected lakehouse/password in credentials"
pass "configure stores lakehouse password in credentials (file backend)"
[[ "$(file_mode "${CRED_FILE}")" == "600" ]] || fail "configure: credentials must be mode 600, got $(file_mode "${CRED_FILE}")"
pass "credentials file is chmod 600"

# ── Task 2: API key per-environment storage ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --api-key atm_prod --env production >/dev/null 2>&1
grep -q '^apikey/production=atm_prod$' "${CRED_FILE}" || fail "configure: expected apikey/production in credentials"
pass "configure stores a per-environment API key"
grep -q '^default_env=production$' "${CONFIG_FILE}" || fail "configure: first env should become default_env"
pass "first configured environment becomes the default"
grep -Eq '^environments=.*production' "${CONFIG_FILE}" || fail "configure: environments should list production"
pass "configure tracks the environment in the environments list"

"${CLI}" configure --api-key atm_stg --env staging >/dev/null 2>&1
grep -q '^default_env=production$' "${CONFIG_FILE}" || fail "configure: default_env should stay production"
pass "a second environment does not change the default"
"${CLI}" configure --api-key atm_stg2 --env staging --default >/dev/null 2>&1
grep -q '^default_env=staging$' "${CONFIG_FILE}" || fail "configure: --default should switch default_env"
pass "--default switches the default environment"

# ── Task 3: stdin secrets & validation ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"

# Declarative guards from bashly.yml (conflicts / needs):
if "${CLI}" configure --password p --password-stdin >/dev/null 2>&1 <<<"x"; then
  fail "configure: --password and --password-stdin together should error"
fi
pass "--password + --password-stdin is rejected (bashly conflicts)"
if "${CLI}" configure --api-key k >/dev/null 2>&1; then
  fail "configure: --api-key without --env should error"
fi
pass "--api-key without --env is rejected (bashly needs)"

# Code guard: --env only applies to --api-key/--default.
if "${CLI}" configure --user u --env production >/dev/null 2>&1; then
  fail "configure: --env with lakehouse-only fields should error"
fi
pass "--env is rejected for a lakehouse-only configure"

# stdin reading:
printf 's_fromstdin' | "${CLI}" configure --user alice --password-stdin >/dev/null 2>&1
grep -q '^lakehouse/password=s_fromstdin$' "${CRED_FILE}" || fail "configure: --password-stdin should store the piped password"
pass "--password-stdin reads the password from stdin"
printf 'atm_fromstdin' | "${CLI}" configure --api-key-stdin --env production >/dev/null 2>&1
grep -q '^apikey/production=atm_fromstdin$' "${CRED_FILE}" || fail "configure: --api-key-stdin should store the piped key"
pass "--api-key-stdin reads the API key from stdin"

# ── Task 4: configure --list ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --user u_blabla --password s_llll >/dev/null 2>&1
"${CLI}" configure --api-key atm_prod --env production >/dev/null 2>&1
OUT="$("${CLI}" configure --list 2>/dev/null)"
echo "${OUT}" | grep -q 'u_blabla' || fail "--list: should show the username"
pass "--list shows the lakehouse username"
echo "${OUT}" | grep -Eq 'password:[[:space:]]*set' || fail "--list: should show password as set"
pass "--list shows the password as set"
if echo "${OUT}" | grep -q 's_llll'; then fail "--list: must NOT print the secret value"; fi
pass "--list never prints a secret value"
echo "${OUT}" | grep -q 'production' || fail "--list: should list the production environment"
pass "--list lists configured environments"
"${CLI}" configure --list >/dev/null 2>&1 || fail "--list: should exit 0 when environments are configured"
pass "--list exits 0 on success"

echo ""
echo -e "${GREEN}All configure tests passed.${NC}"
