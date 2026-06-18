require_jq
response="$(management_request "GET" "/whoami" "")"

ptype="$(printf '%s' "$response" | jq -r '.principal.type // empty')"
pname="$(printf '%s' "$response" | jq -r '.principal.name // empty')"
pemail="$(printf '%s' "$response" | jq -r '.principal.email // empty')"
pslug="$(printf '%s' "$response" | jq -r '.principal.slug // empty')"
oname="$(printf '%s' "$response" | jq -r '.organization.name // empty')"
oslug="$(printf '%s' "$response" | jq -r '.organization.slug // empty')"

if [[ "$ptype" == "ServiceAccount" ]]; then
  printf 'Service account: %s (%s)\n' "$pname" "$pslug"
elif [[ -n "$pemail" ]]; then
  printf 'User: %s <%s>\n' "$pname" "$pemail"
else
  printf 'User: %s\n' "$pname"
fi
printf 'Organization: %s (%s)\n' "$oname" "$oslug"
