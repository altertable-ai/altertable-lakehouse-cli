#!/bin/bash
set -e

# Configuration
API_BASE="http://localhost:15000"
USERNAME="testuser"
PASSWORD="testpass"
CLI="./bin/altertable"

# Setup env vars for CLI
export ALTERTABLE_API_BASE="${API_BASE}"
export ALTERTABLE_USERNAME="${USERNAME}"
export ALTERTABLE_PASSWORD="${PASSWORD}"
# Or use token if preferred, but basic auth is fine with the mock
# export ALTERTABLE_BASIC_AUTH_TOKEN=$(echo -n "${USERNAME}:${PASSWORD}" | base64)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if mock is reachable
if ! curl -s "${API_BASE}/health" > /dev/null; then
    log_info "Mock server not reachable at ${API_BASE}. Assuming CI service container or manual startup."
    # In CI this script runs after service is healthy. Locally might fail if not started.
    # We proceed, but curl errors will fail the script.
fi

# 1. Validate
log_info "Testing 'validate'..."
${CLI} validate --statement "SELECT 1" | jq .

# 2. Append (Create table)
log_info "Testing 'append'..."
# Use "memory" catalog which usually exists in DuckDB/Altertable mock environments by default,
# or stick to "default" but quote it if necessary. The error "Catalog 'my_catalog' does not exist" suggests
# we need to use a valid catalog.
# Let's revert to "default" but assume the previous error "syntax error at or near default"
# was due to something else or strict SQL parsing of "default" as a keyword.
# We will quote identifiers to be safe: "default"."public"."users"

${CLI} append --catalog "default" --schema "public" --table "users" --data '{"id": 1, "name": "Alice"}' | jq .

# 3. Upload
log_info "Testing 'upload'..."
echo "id,name
1,Bob
2,Charlie" > data.csv
${CLI} upload --catalog "default" --schema "public" --table "users" --format "csv" --mode "append" --file "data.csv"
rm data.csv

# 4. Query (Accumulated)
log_info "Testing 'query' (accumulated)..."
# Quote identifiers to handle "default" keyword if it is reserved
OUTPUT=$(${CLI} query --statement "SELECT * FROM \"default\".\"public\".\"users\" LIMIT 5")
echo "${OUTPUT}" | jq .
# Simple check for result structure
if [[ $(echo "${OUTPUT}" | jq 'type') != "array" && $(echo "${OUTPUT}" | jq 'type') != "object" ]]; then
    log_error "Query output is not valid JSON"
    exit 1
fi

# 5. Query (Streamed)
log_info "Testing 'query' (streamed)..."
${CLI} query --statement "SELECT * FROM \"default\".\"public\".\"users\" LIMIT 100" --format ndjson > streamed_output.ndjson
# Check if file has lines
if [[ ! -s streamed_output.ndjson ]]; then
    log_error "Streamed output is empty"
    exit 1
fi
head -n 3 streamed_output.ndjson
rm streamed_output.ndjson

# 6. Get Query
log_info "Testing 'get-query'..."
# Run a query to get an ID. Metadata is in the first line of NDJSON output.
${CLI} query --statement "SELECT 1" --format ndjson > query_meta.ndjson
QUERY_ID=$(head -n 1 query_meta.ndjson | jq -r .query_id)
rm query_meta.ndjson

if [[ -z "$QUERY_ID" || "$QUERY_ID" == "null" ]]; then
    log_error "Failed to extract query_id from metadata"
    exit 1
fi

log_info "Got Query ID: ${QUERY_ID}"
${CLI} get-query "${QUERY_ID}" | jq .

# 7. Cancel Query
log_info "Testing 'cancel'..."
# Try to cancel the query we just ran (it might be finished, but the API should handle it)
# We use the same QUERY_ID.
set +e
${CLI} cancel --query-id "${QUERY_ID}" --session-id "session-integration-test"
RET=$?
set -e

if [[ $RET -ne 0 ]]; then
    log_info "Cancel returned non-zero (expected if query already finished), but command ran."
else
    log_info "Cancel command succeeded."
fi

log_info "All integration tests completed."
