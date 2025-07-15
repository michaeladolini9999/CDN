#!/bin/bash

JSON_FILE="/home/ubuntu/CDN/server.json"

# Thư mục đầu ra
OUT_DIR="/home/ubuntu/CDN/openresty/conf.d"

# Đảm bảo thư mục tồn tại
mkdir -p "$OUT_DIR"

# Trích xuất danh sách cặp [server_name, origin] duy nhất
jq -r '.apps[] | [. [0], .[1]] | @tsv' "$JSON_FILE" | sort -u | while read -r server_name origin; do

  # Tạo wildcard từ server_name
  domain=$(echo "$server_name" | cut -d. -f2-)
  wildcard="wild.$domain"

  # Tạo tên file
  conf_file="$OUT_DIR/$server_name.conf"

  # Nếu có origin
  if [ -n "$origin" ]; then
    cat >> "$conf_file" <<EOF

server {
    listen 9090 ssl;
    http2 on;
    server_name $server_name;
    ssl_certificate     /home/ubuntu/CDN/ssl/$wildcard/fullchain.pem;
    ssl_certificate_key /home/ubuntu/CDN/ssl/$wildcard/privkey.pem;
    ssl_trusted_certificate /home/ubuntu/CDN/ssl/$wildcard/chain.pem;

    root /var/www/html;

    resolver 8.8.8.8 8.8.4.4 valid=60s;

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
        try_files \$uri @proxy_m3u8;
        add_header "Cache-Control" "no-cache";
        add_header "Access-Control-Allow-Origin" "*" always;
        add_header "Access-Control-Expose-Headers" "Content-Length";
        types {
            application/vnd.apple.mpegurl m3u8;
        }
    }

    location @proxy_m3u8 {
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
        proxy_pass https://$origin:9090;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_cache off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
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
        try_files \$uri @proxy_ts;
        add_header "Access-Control-Allow-Origin" "*" always;
        add_header "Access-Control-Expose-Headers" "Content-Length";
        types {
            video/mp2t ts;
        }
    }

    location @proxy_ts {
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
        proxy_pass https://$origin:9090;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering on;
        proxy_buffer_size 16k;
        proxy_buffers 8 128k;
        proxy_busy_buffers_size 256k;
        proxy_temp_file_write_size 256k;

        proxy_cache hls_cache;
        proxy_cache_valid 200 1m;
        proxy_cache_use_stale error timeout updating;
        proxy_ignore_headers Cache-Control Expires Set-Cookie;
        proxy_cache_lock on;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  else
    # Không có origin
    cat >> "$conf_file" <<EOF

server {
    listen 9090 ssl;
    http2 on;
    server_name $server_name;
    ssl_certificate     /home/ubuntu/CDN/ssl/$wildcard/fullchain.pem;
    ssl_certificate_key /home/ubuntu/CDN/ssl/$wildcard/privkey.pem;
    ssl_trusted_certificate /home/ubuntu/CDN/ssl/$wildcard/chain.pem;

    root /var/www/html;

    location /hls/ {
        include /home/ubuntu/CDN/*.allow;
        add_header "Cache-Control" "no-cache";
        add_header "Access-Control-Allow-Origin" "*" always;
        add_header "Access-Control-Expose-Headers" "Content-Length";
        try_files \$uri \$uri/ =404;
        types {
            application/vnd.apple.mpegurl m3u8;
            video/mp2t ts;
        }
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
    }
}
EOF
  fi

  echo "✅ Tạo: $conf_file"
done
