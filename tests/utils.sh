#!/bin/bash
# Test utilities for altertable-lakehouse-cli integration tests

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC} $1"; }
fail() { echo -e "${RED}FAIL${NC} $1"; exit 1; }

# ---------------------------------------------------------------------------
# Curl spy
#
# Interposes a thin wrapper ahead of the real curl in PATH.  The wrapper
# logs every -d (request body) value to a file, then exec's real curl so
# the actual HTTP call still happens.
#
# Lifecycle:
#   setup_curl_spy        – call once before the tests that need it
#   teardown_curl_spy     – call once after; restores PATH
#
# Per-request:
#   run_with_curl_capture <cmd> [args...]
#     Runs a CLI command.  Afterwards two globals are available:
#       CURL_PAYLOAD  – the last -d value sent to curl
#       CURL_RESPONSE – the command's stdout (response body)
# ---------------------------------------------------------------------------

_CURL_SPY_DIR=""
_CURL_SPY_SAVED_PATH=""
CURL_PAYLOAD=""
CURL_RESPONSE=""

setup_curl_spy() {
  _CURL_SPY_SAVED_PATH="${PATH}"
  local real_curl
  real_curl=$(command -v curl)

  _CURL_SPY_DIR=$(mktemp -d)
  export _CURL_SPY_PAYLOAD_LOG="${_CURL_SPY_DIR}/payload.log"
  export _CURL_SPY_REAL_CURL="${real_curl}"

  cat > "${_CURL_SPY_DIR}/curl" << 'WRAPPER'
#!/bin/bash
# Extract and log the -d / --data payload
for ((i=1; i<=$#; i++)); do
  arg="${!i}"
  if [[ "${arg}" == "-d" || "${arg}" == "--data" ]]; then
    next=$((i+1))
    printf '%s\n' "${!next}" > "${_CURL_SPY_PAYLOAD_LOG}"
  fi
done
exec "${_CURL_SPY_REAL_CURL}" "$@"
WRAPPER
  chmod +x "${_CURL_SPY_DIR}/curl"
  export PATH="${_CURL_SPY_DIR}:${PATH}"
}

teardown_curl_spy() {
  if [[ -n "${_CURL_SPY_DIR}" ]]; then
    rm -rf "${_CURL_SPY_DIR}"
  fi
  if [[ -n "${_CURL_SPY_SAVED_PATH}" ]]; then
    export PATH="${_CURL_SPY_SAVED_PATH}"
  fi
}

run_with_curl_capture() {
  CURL_PAYLOAD=""
  CURL_RESPONSE=""
  : > "${_CURL_SPY_PAYLOAD_LOG}"

  CURL_RESPONSE=$("$@" 2>/dev/null)

  if [[ -s "${_CURL_SPY_PAYLOAD_LOG}" ]]; then
    CURL_PAYLOAD=$(cat "${_CURL_SPY_PAYLOAD_LOG}")
  fi
}

# ---------------------------------------------------------------------------
# Assertions on the captured curl payload
# ---------------------------------------------------------------------------

assert_curl_payload_contains() {
  local label="$1"
  local pattern="$2"
  if ! echo "${CURL_PAYLOAD}" | grep -q "${pattern}"; then
    fail "${label}"
  fi
}

assert_curl_payload_not_contains() {
  local label="$1"
  local pattern="$2"
  if echo "${CURL_PAYLOAD}" | grep -q "${pattern}"; then
    fail "${label}"
  fi
}

# ---------------------------------------------------------------------------
# Assertions on the response
# ---------------------------------------------------------------------------

assert_response_json_eq() {
  local label="$1"
  local jq_expr="$2"
  local expected="$3"
  local actual
  actual=$(echo "${CURL_RESPONSE}" | jq -r "${jq_expr}")
  [[ "${actual}" == "${expected}" ]] || fail "${label}: expected '${expected}', got '${actual}'"
}
