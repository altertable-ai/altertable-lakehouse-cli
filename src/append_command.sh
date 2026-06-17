local catalog="${args[--catalog]}"
local schema="${args[--schema]}"
local table="${args[--table]}"
local data="${args[--data]}"

local json_content
if [[ "${data}" == "@"* ]]; then
  local filepath="${data:1}"
  if [[ ! -f "${filepath}" ]]; then
    log_error "File not found: ${filepath}"
    exit 1
  fi
  json_content=$(cat "${filepath}")
else
  json_content="${data}"
fi

local first_char
first_char=$(echo "${json_content}" | tr -d '[:space:]' | head -c 1)

local payload
if [[ "${first_char}" == "[" || "${first_char}" == "{" ]]; then
  if command -v jq >/dev/null 2>&1; then
    payload=$(echo "${json_content}" | jq -c '.')
  else
    payload="${json_content}"
  fi
else
  log_error "Data must be a JSON object or array."
  exit 1
fi

local catalog_enc schema_enc table_enc
catalog_enc=$(urlencode "$catalog")
schema_enc=$(urlencode "$schema")
table_enc=$(urlencode "$table")

local url_params="catalog=${catalog_enc}&schema=${schema_enc}&table=${table_enc}"
http_request "POST" "/append?${url_params}" "${payload}"
