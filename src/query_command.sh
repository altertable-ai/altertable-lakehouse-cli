local statement="${args[--statement]}"
local query_id="${args[--query-id]:-}"
local session_id="${args[--session-id]:-}"
local payload

if command -v jq >/dev/null 2>&1; then
  payload=$(jq -n \
    --arg stmt "$statement" \
    --arg qid "$query_id" \
    --arg sid "$session_id" \
    '{statement: $stmt} +
     (if $qid != "" then {query_id: $qid}   else {} end) +
     (if $sid != "" then {session_id: $sid} else {} end)')
else
  local safe_statement="${statement//\"/\\\"}"
  payload="{\"statement\": \"${safe_statement}\"}"
fi

http_request "POST" "/query" "${payload}" "Content-Type: application/json"
