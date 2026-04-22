#!/bin/bash
set -euo pipefail

API_BASE="http://0.0.0.0:15000"
CLI="./bin/altertable"

export ALTERTABLE_API_BASE="${API_BASE}"
export ALTERTABLE_USERNAME="testuser"
export ALTERTABLE_PASSWORD="testpass"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# ── validate ──────────────────────────────────────────────────────────────────

RESP=$("${CLI}" validate --statement "SELECT 1")
[[ $(echo "${RESP}" | jq -r '.valid') == "true" ]] || fail "validate: expected valid=true"
pass "validate returns valid=true for correct SQL"

RESP=$("${CLI}" validate --statement "NOT VALID SQL !!!")
[[ $(echo "${RESP}" | jq -r '.valid') == "false" ]] || fail "validate: expected valid=false for invalid SQL"
[[ $(echo "${RESP}" | jq -r '.error') != "null" ]] || fail "validate: expected error message for invalid SQL"
pass "validate returns valid=false with error for invalid SQL"

# ── upload (create) ───────────────────────────────────────────────────────────

printf 'id,name\n1,Alice\n2,Bob\n' > /tmp/at_test_upload.csv
"${CLI}" upload \
  --catalog memory --schema main --table cli_test \
  --format csv --mode overwrite \
  --file /tmp/at_test_upload.csv > /dev/null
rm /tmp/at_test_upload.csv
pass "upload creates table from CSV"

# ── query ─────────────────────────────────────────────────────────────────────

RESP=$("${CLI}" query --statement "SELECT * FROM cli_test ORDER BY id")
COLS=$(echo "${RESP}" | sed -n '2p' | jq -r '.[0]')
[[ "${COLS}" == "id" ]] || fail "query: expected first column 'id', got '${COLS}'"

ROW1=$(echo "${RESP}" | sed -n '3p' | jq -r '.[1]')
[[ "${ROW1}" == "Alice" ]] || fail "query: expected first row name 'Alice', got '${ROW1}'"
pass "query returns columns and rows from uploaded table"

# ── query with explicit query_id (used by get-query / cancel) ─────────────────

QID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
SID="b2c3d4e5-f6a7-8901-bcde-f12345678901"

"${CLI}" query --statement "SELECT 42 AS answer" \
  --query-id "${QID}" --session-id "${SID}" > /dev/null
pass "query accepts --query-id and --session-id"

# ── get-query ─────────────────────────────────────────────────────────────────

RESP=$("${CLI}" get-query "${QID}")
[[ $(echo "${RESP}" | jq -r '.uuid') == "${QID}" ]] || fail "get-query: uuid mismatch"
[[ $(echo "${RESP}" | jq -r '.query') == "SELECT 42 AS answer" ]] || fail "get-query: query text mismatch"
pass "get-query returns the query log"

# ── cancel ────────────────────────────────────────────────────────────────────

QID2="c3d4e5f6-a7b8-9012-cdef-123456789012"
SID2="d4e5f6a7-b8c9-0123-defa-234567890123"

"${CLI}" query --statement "SELECT 1" \
  --query-id "${QID2}" --session-id "${SID2}" > /dev/null

RESP=$("${CLI}" cancel --query-id "${QID2}" --session-id "${SID2}")
[[ $(echo "${RESP}" | jq -r '.cancelled') == "true" ]] || fail "cancel: expected cancelled=true"
pass "cancel returns cancelled=true when session_id matches"

RESP=$("${CLI}" cancel --query-id "${QID2}" --session-id "wrong-session")
[[ $(echo "${RESP}" | jq -r '.cancelled') == "false" ]] || fail "cancel: expected cancelled=false for wrong session"
pass "cancel returns cancelled=false for wrong session_id"

# ── append (single datum) ─────────────────────────────────────────────────────

setup_curl_spy

run_with_curl_capture "${CLI}" append \
  --catalog memory --schema main --table cli_test \
  --data '{"id": 3, "name": "Charlie"}'

assert_response_json_eq "append single: ok field" '.ok' 'true'
pass "append single: returns ok=true"

assert_curl_payload_not_contains \
  "append single: payload must not wrap data in 'Single'" '"Single"'
pass "append single: payload is raw JSON without Single wrapper"

RESP=$("${CLI}" query --statement "SELECT COUNT(*) AS n FROM cli_test" 2>/dev/null)
COUNT=$(echo "${RESP}" | sed -n '3p' | jq -r '.[0]')
[[ "${COUNT}" == "3" ]] || fail "append single: expected 3 rows after append, got '${COUNT}'"
pass "query reflects appended row (3 rows total)"

# ── append (batch) ────────────────────────────────────────────────────────────

run_with_curl_capture "${CLI}" append \
  --catalog memory --schema main --table cli_test \
  --data '[{"id": 4, "name": "Delta"}, {"id": 5, "name": "Echo"}]'

assert_response_json_eq "append batch: ok field" '.ok' 'true'
pass "append batch: returns ok=true"

assert_curl_payload_not_contains \
  "append batch: payload must not wrap data in 'Batch'" '"Batch"'
pass "append batch: payload is raw JSON without Batch wrapper"

RESP=$("${CLI}" query --statement "SELECT COUNT(*) AS n FROM cli_test" 2>/dev/null)
COUNT=$(echo "${RESP}" | sed -n '3p' | jq -r '.[0]')
[[ "${COUNT}" == "5" ]] || fail "append batch: expected 5 rows after batch append, got '${COUNT}'"
pass "query reflects batch-appended rows (5 rows total)"

teardown_curl_spy

# ── --debug flag ─────────────────────────────────────────────────────────────

STDERR=$("${CLI}" --debug validate --statement "SELECT 1" 2>&1 >/dev/null)
echo "${STDERR}" | grep -q '\[DEBUG\]' || fail "--debug before command: expected [DEBUG] output on stderr"
echo "${STDERR}" | grep -q '< HTTP/' || fail "--debug before command: expected verbose curl output on stderr"
pass "--debug before command produces debug output"

STDERR=$("${CLI}" validate --debug --statement "SELECT 1" 2>&1 >/dev/null)
echo "${STDERR}" | grep -q '\[DEBUG\]' || fail "--debug after command: expected [DEBUG] output on stderr"
echo "${STDERR}" | grep -q '< HTTP/' || fail "--debug after command: expected verbose curl output on stderr"
pass "--debug after command produces debug output"

echo ""
echo -e "${GREEN}All integration tests passed.${NC}"
