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
rm -f "$OUT_DIR"/*
# Trích xuất danh sách cặp [server_name, origin] duy nhất
jq -r '.apps[] | [. [0], .[1]] | @tsv' "$JSON_FILE" | sort -u | while read -r server_name origin; do

  # Tạo wildcard từ server_name
  domain=$(echo "$server_name" | cut -d. -f2-)
  wildcard="wild.$domain"

  # Tạo tên file
  conf_file="$OUT_DIR/$server_name.conf"

  cat >> "$conf_file" <<EOF

server {
    listen 8080 ssl http2;
    server_name $server_name;
    ssl_certificate /home/ubuntu/CDN/ssl/$wildcard/fullchain.pem;
    ssl_certificate_key /home/ubuntu/CDN/ssl/$wildcard/privkey.pem;
    ssl_trusted_certificate /home/ubuntu/CDN/ssl/$wildcard/chain.pem;

    root /var/www/html;

    location /hls/ {
	deny all;
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

  echo "✅ Tạo: $conf_file"
done
