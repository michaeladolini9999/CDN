#!/bin/bash

JSON_FILE="/home/ubuntu/CDN/server.json"

# Thư mục đầu ra
OUT_DIR="/home/ubuntu/CDN/openresty/conf.d"

# Đảm bảo thư mục tồn tại
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*
# Trích xuất danh sách cặp [server_name, origin] duy nhất
jq -r '.apps[] | [. [0]] | @tsv' "$JSON_FILE" | sort -u | while read -r server_name; do

  # Tạo wildcard từ server_name
  domain=$(echo "$server_name" | cut -d. -f2-)
  wildcard="wild.$domain"

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
        log_by_lua_block {
          local uri = ngx.var.uri
          local ip  = ngx.var.remote_addr
          local bytes = tonumber(ngx.var.body_bytes_sent) or 0
          local app, stream = uri:match("/hls/([^/]+)/([^/]+)")
          if not app then return end

          local stats = ngx.shared.stats
          local base = app..":"..stream

          stats:incr(base..":requests", 1, 0)
          stats:incr(base..":bytes", bytes, 0)

          local ipkey = base..":ip:"..ip
          if not stats:get(ipkey) then
            stats:set(ipkey, true)
            stats:incr(base..":unique", 1, 0)
          end
        }
        try_files \$uri \$uri/../index.m3u8 =404;
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
          local uri = ngx.var.uri
          local ip  = ngx.var.remote_addr
          local bytes = tonumber(ngx.var.body_bytes_sent) or 0
          local app, stream = uri:match("/hls/([^/]+)/([^/]+)")
          if not app then return end

          local stats = ngx.shared.stats
          local base = app..":"..stream

          stats:incr(base..":requests", 1, 0)
          stats:incr(base..":bytes", bytes, 0)

          local ipkey = base..":ip:"..ip
          if not stats:get(ipkey) then
            stats:set(ipkey, true)
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
