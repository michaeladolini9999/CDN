#!/bin/bash
NGINX_FILE="/home/ubuntu/CDN/openresty/nginx.conf"
JSON_FILE="/home/ubuntu/CDN/server.json"

cp /home/ubuntu/CDN/openresty/nginx1.conf  $NGINX_FILE

# Thư mục đầu ra
OUT_DIR="/home/ubuntu/CDN/openresty/conf.d"

# Đảm bảo thư mục tồn tại
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*
# Trích xuất danh sách server_name duy nhất
jq -r '.apps[] | [. [0]] | @tsv' "$JSON_FILE" | sort -u | while read -r server_name; do

  # Tạo wildcard từ server_name
  domain=$(echo "$server_name" | cut -d. -f2-)
  wildcard="wild.$domain"

  search_pattern="listen 9090 default_server;"

# Kiểm tra đã tồn tại chưa
  if grep -qF "$search_pattern" "$NGINX_FILE"; then
    echo "✅ 'listen 9090 default_server;' existed in $NGINX_FILE"
  else
    echo "⚠️  Adding default_server into block http { ... }"
    sed -i '/http\s*{/,/^}/ {
    /^}/ i\
\tserver {\
\t\tlisten 9090 default_server;\
\t\tserver_name _;\
\t\tssl_certificate /home/ubuntu/CDN/ssl/'"$wildcard"'/fullchain.pem;\
\t\tssl_certificate_key /home/ubuntu/CDN/ssl/'"$wildcard"'/privkey.pem;\
\t\tssl_trusted_certificate /home/ubuntu/CDN/ssl/'"$wildcard"'/chain.pem;\
\t\treturn 404;\
\t}
}' "$NGINX_FILE"
    echo "✅ Added block default_server into $NGINX_FILE"
  fi

  # Tạo tên file
  conf_file="$OUT_DIR/$server_name.conf"

  cat >> "$conf_file" <<EOF
server {
    listen 9090 ssl;
    http2 on;
    server_name $server_name;
    ssl_certificate     /home/ubuntu/CDN/ssl/$wildcard/fullchain.pem;
    ssl_certificate_key /home/ubuntu/CDN/ssl/$wildcard/privkey.pem;
    ssl_trusted_certificate /home/ubuntu/CDN/ssl/$wildcard/chain.pem;

    root /var/www/html;

    location ~ \.m3u8\$ {
        include /home/ubuntu/CDN/*.allow;
        try_files \$uri =404;
        add_header "Cache-Control" "no-cache";
        add_header "Access-Control-Allow-Origin" "*" always;
        add_header "Access-Control-Expose-Headers" "Content-Length";
        types {
            application/vnd.apple.mpegurl m3u8;
        }
    }

    location ~ \.ts\$ {
        include /home/ubuntu/CDN/*.allow;
        log_by_lua_block {
          local uri   = ngx.var.uri
          local app, stream = uri:match("/hls/([^/]+)/([^/]+)")
          if not app then return end
          local ip    = ngx.var.remote_addr
          local bytes = tonumber(ngx.var.body_bytes_sent) or 0
          
          local active = ngx.shared.meta:get("active_set") or "A"
          local stats  = ngx.shared["stats_"..active]
          local ips    = ngx.shared["ip_"..active]
          local base   = app..":"..stream

          stats:incr(base..":requests", 1, 0)
          stats:incr(base..":bytes", bytes, 0)

          local ipkey = base..":ip:"..ip
          local ok, err = ips:add(ipkey, true)
          if ok then
            stats:incr(base..":unique", 1, 0)
          end
        }
        try_files \$uri =404;
        add_header "Access-Control-Allow-Origin" "*" always;
        add_header "Access-Control-Expose-Headers" "Content-Length";
        types {
            video/mp2t ts;
        }
    }
}
EOF

  echo "✅ Tạo: $conf_file"
done
