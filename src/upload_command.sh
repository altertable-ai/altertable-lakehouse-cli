local catalog="${args[--catalog]}"
local schema="${args[--schema]}"
local table="${args[--table]}"
local format="${args[--format]}"
local mode="${args[--mode]}"
local primary_key="${args[--primary-key]:-}"
local file="${args[--file]}"

if [[ "${mode}" == "upsert" && -z "${primary_key}" ]]; then
  log_error "--primary-key is required when --mode is upsert."
  exit 1
fi

if [[ ! -f "${file}" ]]; then
  log_error "File not found: ${file}"
  exit 1
fi

local catalog_enc schema_enc table_enc format_enc mode_enc
catalog_enc=$(urlencode "$catalog")
schema_enc=$(urlencode "$schema")
table_enc=$(urlencode "$table")
format_enc=$(urlencode "$format")
mode_enc=$(urlencode "$mode")

local url_params="catalog=${catalog_enc}&schema=${schema_enc}&table=${table_enc}&format=${format_enc}&mode=${mode_enc}"
if [[ -n "${primary_key}" ]]; then
  local pk_enc
  pk_enc=$(urlencode "$primary_key")
  url_params+="&primary_key=${pk_enc}"
fi

http_request "POST" "/upload?${url_params}" "@${file}" "Content-Type: application/octet-stream"
