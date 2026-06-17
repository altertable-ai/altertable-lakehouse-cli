local query_id="${args[query_uuid]}"
local query_id_enc
query_id_enc=$(urlencode "$query_id")
http_request "GET" "/query/${query_id_enc}" ""
