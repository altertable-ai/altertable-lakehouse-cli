get_auth_header() {
  local token user pass
  if [[ -n "${ALTERTABLE_BASIC_AUTH_TOKEN:-}" ]]; then
    echo "Authorization: Basic ${ALTERTABLE_BASIC_AUTH_TOKEN}"
    return 0
  fi
  if [[ -n "${ALTERTABLE_LAKEHOUSE_USERNAME:-}" && -n "${ALTERTABLE_LAKEHOUSE_PASSWORD:-}" ]]; then
    token=$(printf '%s' "${ALTERTABLE_LAKEHOUSE_USERNAME}:${ALTERTABLE_LAKEHOUSE_PASSWORD}" | base64 | tr -d '\n')
    echo "Authorization: Basic ${token}"
    return 0
  fi
  token="$(secret_get 'lakehouse/basic-token')"
  if [[ -n "$token" ]]; then
    echo "Authorization: Basic ${token}"
    return 0
  fi
  user="$(config_get user)"
  pass="$(secret_get 'lakehouse/password')"
  if [[ -n "$user" && -n "$pass" ]]; then
    token=$(printf '%s' "${user}:${pass}" | base64 | tr -d '\n')
    echo "Authorization: Basic ${token}"
    return 0
  fi
  log_error "No credentials. Run 'altertable configure' or set ALTERTABLE_LAKEHOUSE_USERNAME/PASSWORD (or ALTERTABLE_BASIC_AUTH_TOKEN)."
  exit 1
}
