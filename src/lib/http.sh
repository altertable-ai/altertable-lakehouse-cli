http_send() {
  local method="$1"
  local url="$2"
  local auth_header="$3"
  local data="$4"
  local extra_headers=("${@:5}")

  local user_agent="altertable-lakehouse-cli/${version}"

  local curl_opts=(
    -s
    -X "${method}"
    -H "${auth_header}"
    -H "User-Agent: ${user_agent}"
    -w "%{http_code}"
  )

  if [[ "${args[--debug]:-}" ]]; then
    curl_opts+=(-v)
  fi

  if [[ -n "${data}" ]]; then
    if [[ "${data}" == "@"* ]]; then
      curl_opts+=(--upload-file "${data:1}")
    else
      curl_opts+=(-H "Content-Type: application/json")
      curl_opts+=(-d "${data}")
    fi
  fi

  for h in "${extra_headers[@]}"; do
    curl_opts+=(-H "${h}")
  done

  log_debug "Request: ${method} ${url}"

  local response_body
  local http_code
  local response_file
  response_file=$(mktemp)

  http_code=$(curl "${curl_opts[@]}" -o "${response_file}" "${url}")
  local curl_exit_code=$?

  if [[ $curl_exit_code -ne 0 ]]; then
    log_error "Request failed (curl error: ${curl_exit_code})."
    rm -f "${response_file}"
    exit 1
  fi

  response_body=$(cat "${response_file}")
  rm -f "${response_file}"

  if [[ "${http_code}" -ge 200 && "${http_code}" -lt 300 ]]; then
    echo "${response_body}"
  else
    http_report_error "${http_code}" "${response_body}"
    exit 1
  fi
}

# Map an HTTP status code to a short, human-friendly status line.
http_status_message() {
  local code="$1"
  case "${code}" in
    401) echo "Authentication failed (401). Check your API key." ;;
    403) echo "Permission denied (403)." ;;
    404) echo "Not found (404)." ;;
    429) echo "Rate limited (429). Try again later." ;;
    5*)  echo "Server error (${code}). Try again later." ;;
    *)   echo "Request failed with status ${code}." ;;
  esac
}

# Report a non-2xx response: always a friendly status line, plus a detail line
# only when the body is JSON. Non-JSON bodies (e.g. HTML error pages) are
# suppressed unless --debug is set, so they never leak to normal output.
http_report_error() {
  local code="$1"
  local body="$2"

  log_error "$(http_status_message "${code}")"

  # Trim leading whitespace to inspect the first significant character.
  local trimmed="${body#"${body%%[![:space:]]*}"}"
  if [[ "${trimmed}" == "{"* || "${trimmed}" == "["* ]]; then
    local detail=""
    if command -v jq >/dev/null 2>&1; then
      detail="$(printf '%s' "${body}" | jq -r '(.error.message // .message // .error // empty)' 2>/dev/null)"
      if [[ -n "${detail}" ]]; then
        log_error "${detail}"
      else
        log_error "Response: $(printf '%s' "${body}" | jq -c '.' 2>/dev/null || printf '%s' "${body}")"
      fi
    else
      log_error "Response: ${body}"
    fi
  elif [[ -n "${trimmed}" ]]; then
    log_debug "Response body: ${body}"
  fi
}

http_request() {
  local method="$1"
  local endpoint="$2"
  local data="$3"
  local extra_headers=("${@:4}")

  local url; url="$(resolve_api_base)${endpoint}"
  local auth_header
  auth_header=$(get_auth_header)

  http_send "${method}" "${url}" "${auth_header}" "${data}" "${extra_headers[@]}"
}
