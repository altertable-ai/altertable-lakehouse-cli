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
    log_error "HTTP Request failed with status ${http_code}"
    if [[ -n "${response_body}" ]]; then
      log_error "Response: ${response_body}"
    fi
    exit 1
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
