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

echo ""
echo -e "${GREEN}All configure tests passed.${NC}"
