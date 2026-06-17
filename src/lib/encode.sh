urlencode() {
  local string="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$string"
  elif command -v perl >/dev/null 2>&1; then
    perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$string"
  else
    echo "${string// /%20}"
  fi
}
