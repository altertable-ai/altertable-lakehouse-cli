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
configure_run_list() {
  local user api_base app_base default_env e found=0
  user="$(config_get user)"
  api_base="$(resolve_api_base)"
  app_base="$(resolve_app_base)"
  default_env="$(config_get default_env)"

  printf 'Altertable CLI configuration\n'
  printf '  Config dir:    %s\n' "$(config_dir)"
  printf '  Secret store:  %s\n' "$(secret_backend)"
  printf '\n  Lakehouse (data plane):\n'
  printf '    user:        %s\n' "${user:-(not set)}"
  if secret_exists "lakehouse/password"; then printf '    password:    set\n'; else printf '    password:    (not set)\n'; fi
  if secret_exists "lakehouse/basic-token"; then printf '    basic-token: set\n'; fi
  printf '    api_base:    %s\n' "$api_base"
  printf '\n  Management API keys (by environment):\n'
  printf '    app_base:    %s\n' "$app_base"
  printf '    default env: %s\n' "${default_env:-(none)}"
  while IFS= read -r e; do
    [[ -z "$e" ]] && continue
    found=1
    if secret_exists "apikey/${e}"; then printf '    %s: set\n' "$e"; else printf '    %s: (listed, no key)\n' "$e"; fi
  done < <(config_envs)
  [[ "$found" -eq 0 ]] && printf '    (none configured)\n'
  return 0
}
configure_run_remove() { log_error "configure --remove not yet available"; exit 1; }
