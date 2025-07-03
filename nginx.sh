#!/bin/bash

NGINX_FILE="/home/ubuntu/CDN/nginx/nginx.conf"
JSON_FILE="/home/ubuntu/CDN/server.json"

cat /home/ubuntu/CDN/nginx/nginx1.conf > $NGINX_FILE

cat <<EOL >> "$NGINX_FILE"
rtmp {
    server {
        listen 1935;
        chunk_size 4096;
        notify_method get;
        allow publish all;
        drop_idle_publisher 60s;
EOL

declare -A apps_added

jq -r '.apps[][2]' "$JSON_FILE" | sort -u | while read -r app_name; do
    if [[ -z "${apps_added[$app_name]}" ]]; then
        cat <<EOL >> "$NGINX_FILE"

        application $app_name {
            live on;
            on_publish http://127.0.0.1:81/rtmp/;
            hls on;
            hls_path /var/www/html/hls/$app_name;
            hls_cleanup off;
            hls_continuous on;
            hls_nested on;
            hls_fragment 2s;
            hls_playlist_length 6s;
        }
EOL
        apps_added[$app_name]=1
    fi
done

echo "  }" >> "$NGINX_FILE"
echo "}" >> "$NGINX_FILE"

# Thư mục đầu ra
OUT_DIR="/home/ubuntu/CDN/nginx/conf.d"

# Đảm bảo thư mục tồn tại
mkdir -p "$OUT_DIR"

# Trích xuất danh sách cặp [server_name, origin] duy nhất
jq -r '.apps[] | [. [0], .[1]] | @tsv' "$JSON_FILE" | sort -u | while read -r server_name origin; do

  # Tạo wildcard từ server_name
  domain=$(echo "$server_name" | cut -d. -f2-)
  wildcard="wild.$domain"

  # Tạo tên file
  conf_file="$OUT_DIR/$server_name.conf"

  # Viết phần đầu file: luôn có
  cat > "$conf_file" <<EOF
server {
    listen 5000 ssl http2;
    server_name $server_name;
    ssl_certificate /home/ubuntu/CDN/ssl/$wildcard/fullchain.pem;
    ssl_certificate_key /home/ubuntu/CDN/ssl/$wildcard/privkey.pem;
    ssl_trusted_certificate /home/ubuntu/CDN/ssl/$wildcard/chain.pem;
    location / {
        include proxy_params;
        proxy_pass http://unix:/var/run/cms/cms.sock;
    }
}
EOF

  # Nếu có origin
  if [ -n "$origin" ]; then
    cat >> "$conf_file" <<EOF

server {
    listen 8080 ssl http2;
    server_name $server_name;
    ssl_certificate /home/ubuntu/CDN/ssl/$wildcard/fullchain.pem;
    ssl_certificate_key /home/ubuntu/CDN/ssl/$wildcard/privkey.pem;
    ssl_trusted_certificate /home/ubuntu/CDN/ssl/$wildcard/chain.pem;

    root /var/www/html;

    resolver 8.8.8.8 8.8.4.4 valid=60s;

    location ~ \.m3u8\$ {
        include /home/ubuntu/CDN/*.allow;
        try_files \$uri @proxy_m3u8;
        add_header "Cache-Control" "no-cache";
        add_header "Access-Control-Allow-Origin" "*" always;
        add_header "Access-Control-Expose-Headers" "Content-Length";
        types {
            application/vnd.apple.mpegurl m3u8;
        }
    }

    location @proxy_m3u8 {
        proxy_pass https://$origin:8080;
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
        try_files \$uri @proxy_ts;
        add_header "Access-Control-Allow-Origin" "*" always;
        add_header "Access-Control-Expose-Headers" "Content-Length";
        types {
            video/mp2t ts;
        }
    }

    location @proxy_ts {
        proxy_pass https://$origin:8080;
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

    location /statistics {
        rtmp_stat all;
        rtmp_stat_stylesheet stat.xsl;
    }

    location /stat.xsl {
        root /var/www/html/rtmp;
    }

    location /control {
        rtmp_control all;
    }
}
EOF

  else
    # Không có origin
    cat >> "$conf_file" <<EOF

server {
    listen 8080 ssl http2;
    server_name $server_name;
    ssl_certificate /home/ubuntu/CDN/ssl/$wildcard/fullchain.pem;
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
    }

    location /hlsplayer {
        index hlsplayer.html;
    }

    location /statistics {
        rtmp_stat all;
        rtmp_stat_stylesheet stat.xsl;
    }

    location /stat.xsl {
        root /var/www/html/rtmp;
    }

    location /control {
        rtmp_control all;
    }
}
EOF
  fi

  echo "✅ Tạo: $conf_file"
done
