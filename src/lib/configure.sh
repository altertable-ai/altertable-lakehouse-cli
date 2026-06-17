# Operations behind `altertable configure`. These read the global `args` array
# (set by bashly), consistent with the other libraries.

configure_run_set() {
  local user="${args[--user]:-}"
  local password="${args[--password]:-}"
  local basic_token="${args[--basic-token]:-}"
  local api_key="${args[--api-key]:-}"
  local api_base="${args[--api-base]:-}"
  local app_base="${args[--app-base]:-}"
  local env="${args[--env]:-}"

  # === stdin + --env validation: see Task 3 ===

  # Interactive when nothing was provided.
  if [[ -z "$user" && -z "$password" && -z "$basic_token" && -z "$api_key" \
        && -z "$api_base" && -z "$app_base" && -z "$env" \
        && -z "${args[--password-stdin]:-}" && -z "${args[--api-key-stdin]:-}" \
        && -z "${args[--default]:-}" ]]; then
    configure_run_interactive
    return
  fi

  # Lakehouse credentials (global).
  [[ -n "$user" ]] && config_set user "$user"
  [[ -n "$password" ]] && secret_set "lakehouse/password" "$password"
  [[ -n "$basic_token" ]] && secret_set "lakehouse/basic-token" "$basic_token"
  [[ -n "$api_base" ]] && config_set api_base "$api_base"
  [[ -n "$app_base" ]] && config_set app_base "$app_base"

  # === management API key: see Task 2 ===

  printf 'Configuration updated.\n' >&2
}

# Stubs replaced in later tasks.
configure_run_interactive() { log_error "interactive configure not yet available"; exit 1; }
configure_run_list() { log_error "configure --list not yet available"; exit 1; }
configure_run_remove() { log_error "configure --remove not yet available"; exit 1; }
