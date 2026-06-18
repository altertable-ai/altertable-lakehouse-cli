# Management REST API helpers (app.altertable.ai/rest/v1). Bearer auth, env-scoped.
# Distinct from the data plane (api.altertable.ai, Basic auth) in src/lib/http.sh.

resolve_management_api_base() {
  echo "${ALTERTABLE_MANAGEMENT_API_BASE:-https://app.altertable.ai/rest/v1}"
}

# Echo "Authorization: Bearer <key>" from ALTERTABLE_API_KEY or the stored api-key secret.
get_management_auth_header() {
  local key="${ALTERTABLE_API_KEY:-}"
  if [[ -z "$key" ]] && secret_exists "api-key"; then
    key="$(secret_get 'api-key')"
  fi
  if [[ -z "$key" ]]; then
    log_error "No management API key. Run 'altertable configure --api-key atm_xxx --env <name>' or set ALTERTABLE_API_KEY."
    exit 1
  fi
  echo "Authorization: Bearer ${key}"
}

# Environment slug: ALTERTABLE_ENV, else the stored api_key_env. May be empty.
management_env() {
  local env="${ALTERTABLE_ENV:-}"
  [[ -z "$env" ]] && env="$(config_get api_key_env)"
  printf '%s' "$env"
}

# Environment slug, required.
require_management_env() {
  local env; env="$(management_env)"
  if [[ -z "$env" ]]; then
    log_error "No environment set. Run 'altertable configure --api-key atm_xxx --env <name>' or set ALTERTABLE_ENV."
    exit 1
  fi
  printf '%s' "$env"
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    log_error "This command requires 'jq'. Install it: https://jqlang.github.io/jq/"
    exit 1
  fi
}

management_request() {
  local method="$1"
  local endpoint="$2"
  local data="$3"
  local extra_headers=("${@:4}")

  local url; url="$(resolve_management_api_base)${endpoint}"
  local auth_header
  auth_header=$(get_management_auth_header)

  http_send "${method}" "${url}" "${auth_header}" "${data}" "${extra_headers[@]}"
}
