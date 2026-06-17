get_auth_header() {
  if [[ -n "${ALTERTABLE_BASIC_AUTH_TOKEN:-}" ]]; then
    echo "Authorization: Basic ${ALTERTABLE_BASIC_AUTH_TOKEN}"
  elif [[ -n "${ALTERTABLE_LAKEHOUSE_USERNAME:-}" && -n "${ALTERTABLE_LAKEHOUSE_PASSWORD:-}" ]]; then
    local token
    token=$(echo -n "${ALTERTABLE_LAKEHOUSE_USERNAME}:${ALTERTABLE_LAKEHOUSE_PASSWORD}" | base64 | tr -d '\n')
    echo "Authorization: Basic ${token}"
  else
    log_error "Missing authentication. Set ALTERTABLE_LAKEHOUSE_USERNAME/PASSWORD or ALTERTABLE_BASIC_AUTH_TOKEN."
    exit 1
  fi
}
