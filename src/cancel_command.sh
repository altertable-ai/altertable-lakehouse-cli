local query_id="${args[--query-id]}"
local session_id="${args[--session-id]}"
local query_id_enc session_id_enc
query_id_enc=$(urlencode "$query_id")
session_id_enc=$(urlencode "$session_id")
http_request "DELETE" "/query/${query_id_enc}?session_id=${session_id_enc}" ""
