require_jq

engine="${args[--engine]}"
name="${args[--name]}"

if [[ "$engine" != "altertable" ]]; then
  log_error "Only the 'altertable' engine is supported (got '${engine}')."
  exit 1
fi

env="$(require_management_env)"
body="$(jq -cn --arg name "$name" '{name: $name, engine: "altertable"}')"

response="$(management_request "POST" "/environments/${env}/databases" "$body")"

cslug="$(printf '%s' "$response" | jq -r '(.database // .connection).slug // empty')"
cname="$(printf '%s' "$response" | jq -r '(.database // .connection).name // empty')"
cengine="$(printf '%s' "$response" | jq -r '(.database // .connection).engine // "altertable"')"
[[ -z "$cname" ]] && cname="$name"

printf 'Created catalog "%s" (slug: %s, engine: %s, environment: %s).\n' \
  "$cname" "$cslug" "$cengine" "$env"
