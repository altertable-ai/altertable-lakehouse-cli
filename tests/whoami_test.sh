#!/usr/bin/env bash
# Offline tests for `altertable whoami` output formatting.
set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
CLI="${SCRIPT_DIR}/../bin/altertable"

TEST_HOME="$(mktemp -d)"
export ALTERTABLE_CONFIG_HOME="${TEST_HOME}"
export ALTERTABLE_SECRET_BACKEND=file
export ALTERTABLE_API_KEY=atm_test
unset ALTERTABLE_ENV ALTERTABLE_MANAGEMENT_API_BASE 2>/dev/null || true
cleanup() { rm -rf "${TEST_HOME}"; }
trap cleanup EXIT

# Fake curl returning a caller-supplied body via $_BODY.
mock_curl_body() {
  _D="$(mktemp -d)"
  cat > "${_D}/curl" <<MOCK
#!/usr/bin/env bash
out=""; prev=""
for arg in "\$@"; do case "\$prev" in -o) out="\$arg" ;; esac; prev="\$arg"; done
[[ -n "\$out" ]] && printf '%s' '${_BODY}' > "\$out"
printf '200'
MOCK
  chmod +x "${_D}/curl"; _SP="${PATH}"; export PATH="${_D}:${PATH}"
}
unmock_curl() { export PATH="${_SP}"; rm -rf "${_D}"; }

# ── User principal ──
_BODY='{"principal":{"type":"User","name":"Jane Doe","email":"jane@x.io"},"organization":{"name":"Acme","slug":"acme"}}'
mock_curl_body
OUT="$("${CLI}" whoami 2>/dev/null)"
unmock_curl
echo "${OUT}" | grep -Fq 'User: Jane Doe <jane@x.io>' || fail "whoami user line wrong: '${OUT}'"
echo "${OUT}" | grep -Fq 'Organization: Acme (acme)' || fail "whoami org line wrong: '${OUT}'"
pass "whoami formats a User principal"

# ── ServiceAccount principal ──
_BODY='{"principal":{"type":"ServiceAccount","name":"ci-bot","slug":"ci-bot"},"organization":{"name":"Acme","slug":"acme"}}'
mock_curl_body
OUT="$("${CLI}" whoami 2>/dev/null)"
unmock_curl
echo "${OUT}" | grep -Fq 'Service account: ci-bot (ci-bot)' || fail "whoami service-account line wrong: '${OUT}'"
pass "whoami formats a ServiceAccount principal"

echo ""
echo -e "${GREEN}All whoami tests passed.${NC}"
