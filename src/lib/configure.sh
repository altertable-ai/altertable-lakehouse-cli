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

  # Read secrets from stdin when requested (mutual exclusion is enforced by bashly).
  if [[ -n "${args[--password-stdin]:-}" ]]; then IFS= read -r password || true; fi
  if [[ -n "${args[--api-key-stdin]:-}" ]]; then IFS= read -r api_key || true; fi

  # --env applies only to --api-key/--default; lakehouse credentials are global.
  if [[ -n "$env" && -z "$api_key" && -z "${args[--api-key-stdin]:-}" && -z "${args[--default]:-}" ]]; then
    log_error "--env applies only to --api-key/--default; lakehouse credentials are global."
    exit 1
  fi

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

  # Management API key (per environment; --env is guaranteed present by bashly `needs`).
  if [[ -n "$api_key" ]]; then
    secret_set "apikey/${env}" "$api_key"
    config_add_env "$env"
    if [[ -z "$(config_get default_env)" || -n "${args[--default]:-}" ]]; then
      config_set default_env "$env"
    fi
  elif [[ -n "${args[--default]:-}" ]]; then
    config_env_exists "$env" || { log_error "Unknown environment '${env}'. Configure an API key for it first."; exit 1; }
    config_set default_env "$env"
  fi

  printf 'Configuration updated.\n' >&2
}

# Stubs replaced in later tasks.
configure_run_interactive() { log_error "interactive configure not yet available"; exit 1; }
configure_run_list() { log_error "configure --list not yet available"; exit 1; }
configure_run_remove() { log_error "configure --remove not yet available"; exit 1; }
