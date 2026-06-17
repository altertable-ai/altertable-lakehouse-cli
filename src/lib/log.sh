log_debug() {
  if [[ "${args[--debug]:-}" ]]; then
    echo "[DEBUG] $1" >&2
  fi
}

log_error() {
  echo "[ERROR] $1" >&2
}
