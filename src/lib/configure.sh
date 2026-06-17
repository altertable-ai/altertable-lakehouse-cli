# Operations behind `altertable configure`. These read the global `args` array
# (set by bashly), consistent with the other libraries. A new `configure` always
# REPLACES any previously stored credential — mechanisms are never combined.

# Remove every stored credential and auth identity.
configure_clear_all() {
  secret_delete "lakehouse/password"
  secret_delete "lakehouse/basic-token"
  secret_delete "api-key"
  config_unset user
  config_unset api_key_env
}

configure_run_set() {
  local user="${args[--user]:-}"
  local password="${args[--password]:-}"
  local basic_token="${args[--basic-token]:-}"
  local api_key="${args[--api-key]:-}"
  local env="${args[--env]:-}"
  local want_pw_stdin="${args[--password-stdin]:-}"
  local want_key_stdin="${args[--api-key-stdin]:-}"

  # No input at all -> interactive lakehouse setup.
  if [[ -z "$user$password$basic_token$api_key$env$want_pw_stdin$want_key_stdin" ]]; then
    configure_run_interactive
    return 0
  fi

  if [[ -n "$want_pw_stdin" ]]; then IFS= read -r password || true; fi
  if [[ -n "$want_key_stdin" ]]; then IFS= read -r api_key || true; fi

  # Identify the requested mechanism; at most one is allowed.
  local m_lakehouse="" m_token="" m_apikey="" count=0
  [[ -n "$user" || -n "$password" ]] && m_lakehouse=1
  [[ -n "$basic_token" ]] && m_token=1
  [[ -n "$api_key" ]] && m_apikey=1
  [[ -n "$m_lakehouse" ]] && count=$((count + 1))
  [[ -n "$m_token" ]] && count=$((count + 1))
  [[ -n "$m_apikey" ]] && count=$((count + 1))

  if [[ "$count" -gt 1 ]]; then
    log_error "Choose a single authentication mechanism: --user/--password, --basic-token, or --api-key (they cannot be combined)."
    exit 1
  fi
  if [[ -n "$env" && -z "$m_apikey" ]]; then
    log_error "--env applies only to --api-key."
    exit 1
  fi
  if [[ "$count" -eq 0 ]]; then
    log_error "Nothing to configure. Use --user/--password, --basic-token, or --api-key --env <name>."
    exit 1
  fi
  if [[ -n "$m_lakehouse" && ( -z "$user" || -z "$password" ) ]]; then
    log_error "--user and --password must be provided together."
    exit 1
  fi
  if [[ -n "$m_apikey" && -z "$env" ]]; then
    log_error "--api-key requires --env <name>."
    exit 1
  fi

  # Override: a new configuration replaces any previous one.
  configure_clear_all
  if [[ -n "$m_apikey" ]]; then
    secret_set "api-key" "$api_key"
    config_set api_key_env "$env"
  elif [[ -n "$m_token" ]]; then
    secret_set "lakehouse/basic-token" "$basic_token"
  else
    config_set user "$user"
    secret_set "lakehouse/password" "$password"
  fi
  printf 'Configuration updated.\n' >&2
}

configure_run_interactive() {
  local current_user user password
  current_user="$(config_get user)"
  if [[ -n "$current_user" ]]; then
    printf 'Lakehouse username [%s]: ' "$current_user" >&2
  else
    printf 'Lakehouse username: ' >&2
  fi
  IFS= read -r user || true
  [[ -z "$user" ]] && user="$current_user"
  printf 'Lakehouse password (input hidden): ' >&2
  IFS= read -rs password || true
  printf '\n' >&2
  [[ -z "$user" ]] && { log_error "Username is required."; exit 1; }
  [[ -z "$password" ]] && { log_error "Password is required."; exit 1; }
  configure_clear_all
  config_set user "$user"
  secret_set "lakehouse/password" "$password"
  printf 'Saved lakehouse credentials for user %s.\n' "$user" >&2
}

configure_run_show() {
  local store_display
  case "$(secret_backend)" in
    macos) store_display="MacOS keychain" ;;
    *)     store_display="$(credentials_file)" ;;
  esac
  printf 'Altertable CLI configuration\n'
  printf '  Config dir:    %s\n' "$(config_dir)"
  printf '  Secret store:  %s\n' "$store_display"
  printf '  Data plane:    %s\n' "$(resolve_api_base)"
  printf '\n'
  if secret_exists "api-key"; then
    printf '  Authentication: management API key\n'
    printf '    environment:  %s\n' "$(config_get api_key_env)"
    printf '    api key:      set\n'
  elif secret_exists "lakehouse/basic-token"; then
    printf '  Authentication: lakehouse Basic token\n'
    printf '    basic token:  set\n'
  elif secret_exists "lakehouse/password"; then
    printf '  Authentication: lakehouse username/password\n'
    printf '    user:         %s\n' "$(config_get user)"
    printf '    password:     set\n'
  else
    printf '  No credentials configured. Run: altertable configure\n'
  fi
  return 0
}

configure_run_clear() {
  configure_clear_all
  rm -f "$(config_file)" "$(credentials_file)"
  printf 'Cleared all altertable configuration.\n' >&2
  return 0
}
