require_jq
env="$(require_management_env)"

databases="$(management_request "GET" "/environments/${env}/databases" "")"
connections="$(management_request "GET" "/environments/${env}/connections" "")"

# Emit tab-separated rows: TYPE, NAME, SLUG, ENGINE, CATALOG. Databases first.
rows="$(
  {
    printf '%s' "$databases" | jq -r '
      (.databases // [])[] |
      ["database", (.name // ""), (.slug // ""), (.engine // ""), (.catalog // "")] | @tsv'
    printf '%s' "$connections" | jq -r '
      (.connections // [])[] |
      ["connection", (.name // ""), (.slug // ""), (.engine // ""), (.catalog // "")] | @tsv'
  }
)"

if [[ -z "$rows" ]]; then
  printf 'No catalogs found.\n'
  exit 0
fi

{
  printf 'TYPE\tNAME\tSLUG\tENGINE\tCATALOG\n'
  printf '%s\n' "$rows"
} | column -t -s "$(printf '\t')"
