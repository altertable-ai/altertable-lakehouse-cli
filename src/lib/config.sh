# Non-secret configuration: a flat "key=value" file plus base-URL resolution.

trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

config_dir() { echo "${ALTERTABLE_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/altertable}"; }
config_file() { echo "$(config_dir)/config"; }
credentials_file() { echo "$(config_dir)/credentials"; }

# Flat "key=value" helpers (tolerant of surrounding whitespace, comments preserved).
kv_get() {
  local file="$1" key="$2" line k
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in ''|'#'*) continue ;; esac
    k="$(trim "${line%%=*}")"
    if [[ "$k" == "$key" ]]; then
      trim "${line#*=}"
      printf '\n'
      return 0
    fi
  done < "$file"
  return 0
}

kv_set() {
  local file="$1" key="$2" value="$3" tmp line k found=0
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      k="$(trim "${line%%=*}")"
      if [[ "$k" == "$key" ]]; then
        printf '%s=%s\n' "$key" "$value" >> "$tmp"
        found=1
      else
        printf '%s\n' "$line" >> "$tmp"
      fi
    done < "$file"
  fi
  [[ "$found" -eq 0 ]] && printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
}

kv_unset() {
  local file="$1" key="$2" tmp line k
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    k="$(trim "${line%%=*}")"
    [[ "$k" == "$key" ]] && continue
    printf '%s\n' "$line" >> "$tmp"
  done < "$file"
  mv "$tmp" "$file"
}

config_get() { kv_get "$(config_file)" "$1"; }
config_set() { local f; f="$(config_file)"; kv_set "$f" "$1" "$2"; chmod 600 "$f" 2>/dev/null || true; }
config_unset() { kv_unset "$(config_file)" "$1"; }

resolve_api_base() { echo "${ALTERTABLE_API_BASE:-https://api.altertable.ai}"; }
