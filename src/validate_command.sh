local statement="${args[--statement]}"
local payload

if command -v jq >/dev/null 2>&1; then
  payload=$(jq -n --arg stmt "$statement" '{statement: $stmt}')
else
  local safe_statement="${statement//\"/\\\"}"
  payload="{\"statement\": \"${safe_statement}\"}"
fi

http_request "POST" "/validate" "${payload}" "Content-Type: application/json"
