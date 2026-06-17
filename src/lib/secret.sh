# Secret storage: macOS Keychain when available, otherwise a 0600 file.
# Accounts: lakehouse/password, lakehouse/basic-token, api-key. Service: "altertable".
# We refuse to read the fallback file if its permissions are looser than 600.

_file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }

# Refuse to read the credentials file when group/other have any access.
_require_safe_credentials_file() {
  local f mode
  f="$(credentials_file)"
  [[ -f "$f" ]] || return 0
  mode="$(_file_mode "$f")"
  [[ -n "$mode" ]] || return 0
  if (( (8#$mode) & 8#077 )); then
    log_error "Refusing to read ${f}: permissions ${mode} are too open (group/other access). Run: chmod 600 ${f}"
    exit 1
  fi
}

_warn_file_backend_once() {
  if [[ -z "${_FILE_BACKEND_WARNED:-}" ]]; then
    log_warn "No macOS keychain; storing secrets at $(credentials_file) (chmod 600). Prefer environment variables in CI."
    _FILE_BACKEND_WARNED=1
  fi
}

secret_backend() {
  local override="${ALTERTABLE_SECRET_BACKEND:-}"
  case "$override" in
    file) echo "file"; return 0 ;;
    keychain)
      if [[ "$(uname)" == "Darwin" ]] && command -v security >/dev/null 2>&1; then
        echo "macos"; return 0
      fi
      log_error "ALTERTABLE_SECRET_BACKEND=keychain but the macOS keychain is unavailable."
      exit 1
      ;;
  esac
  if [[ "$(uname)" == "Darwin" ]] && command -v security >/dev/null 2>&1; then
    echo "macos"
  else
    echo "file"
  fi
}

secret_set() {
  local account="$1" value="$2" f
  case "$(secret_backend)" in
    macos) security add-generic-password -U -s "altertable" -a "$account" -w "$value" >/dev/null 2>&1 \
             || { log_error "Failed to store secret in macOS keychain ($account)."; exit 1; } ;;
    file)
      f="$(credentials_file)"
      kv_set "$f" "$account" "$value"
      chmod 600 "$f"
      _warn_file_backend_once
      ;;
  esac
}

secret_get() {
  local account="$1" val=""
  case "$(secret_backend)" in
    macos) val="$(security find-generic-password -s "altertable" -a "$account" -w 2>/dev/null || true)" ;;
    file)  _require_safe_credentials_file; val="$(kv_get "$(credentials_file)" "$account")" ;;
  esac
  printf '%s' "$val"
}

secret_exists() {
  local account="$1"
  case "$(secret_backend)" in
    macos) security find-generic-password -s "altertable" -a "$account" >/dev/null 2>&1 ;;
    file)  _require_safe_credentials_file; [[ -n "$(kv_get "$(credentials_file)" "$account")" ]] ;;
  esac
}

secret_delete() {
  local account="$1"
  case "$(secret_backend)" in
    macos) security delete-generic-password -s "altertable" -a "$account" >/dev/null 2>&1 || true ;;
    file)  kv_unset "$(credentials_file)" "$account" ;;
  esac
}
