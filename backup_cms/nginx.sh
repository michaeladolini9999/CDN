#!/bin/bash

nginx_conf="/home/ubuntu/CDN/nginx/nginx.conf"
server_json="/home/ubuntu/CDN/server.json"

cat /home/ubuntu/CDN/nginx/nginx1.conf > $nginx_conf

server_names=$(jq -r '.apps[][0]' "$server_json" | sort -u)

server_block_template='
server {
    listen 5000 ssl http2;
    server_name %s;
    ssl_certificate /home/ubuntu/CDN/ssl/%s/fullchain.pem;
    ssl_certificate_key /home/ubuntu/CDN/ssl/%s/privkey.pem;
    ssl_trusted_certificate /home/ubuntu/CDN/ssl/%s/chain.pem;
    location / {
        include proxy_params;
        proxy_pass http://unix:/var/run/cms/cms.sock;
    }
}

server {
    listen 5000 ssl http2;
    server_name %s;
    ssl_certificate /home/ubuntu/CDN/ssl/%s/fullchain.pem;
    ssl_certificate_key /home/ubuntu/CDN/ssl/%s/privkey.pem;
    ssl_trusted_certificate /home/ubuntu/CDN/ssl/%s/chain.pem;
    location / {
        include proxy_params;
        proxy_pass http://unix:/var/run/backup_cms/backup_cms.sock;
    }
}
 
server {
    listen 8080 ssl http2;
    server_name %s;
    ssl_certificate /home/ubuntu/CDN/ssl/%s/fullchain.pem;
    ssl_certificate_key /home/ubuntu/CDN/ssl/%s/privkey.pem;
    ssl_trusted_certificate /home/ubuntu/CDN/ssl/%s/chain.pem;

    location / {
        add_header "Cache-Control" "no-cache";
        add_header "Access-Control-Allow-Origin" "*" always;
        add_header "Access-Control-Expose-Headers" "Content-Length";

        if ($request_method = "OPTIONS") {
            add_header "Access-Control-Allow-Origin" "*";
            add_header "Access-Control-Max-Age" 1728000;
            add_header "Content-Type" "text/plain charset=UTF-8";
            add_header "Content-Length" 0;
            return 204;
        }

        types {
            application/dash+xml mpd;
            application/vnd.apple.mpegurl m3u8;
            video/mp2t ts;
        }
        root /var/www/html;
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
'

{
    echo ""
    for name in $server_names; do
        wild_domain="wild.${name#*.}"
        printf "$server_block_template" "$name" "$wild_domain" "$wild_domain" "$wild_domain" "$name" "$wild_domain" "$wild_domain" "$wild_domain"
    done
} >> "$nginx_conf"

cat /home/ubuntu/CDN/nginx/nginx2.conf >> $nginx_conf

cat <<EOL >> "$nginx_conf"
rtmp {
    server {
        listen 1935;
        chunk_size 4096;
        notify_method get;
        allow publish all;
EOL

declare -A apps_added

grep -oP '\["[^"]+","[^"]+' "$server_json" | while IFS="," read -r _ app_name; do
    app_name=$(echo "$app_name" | tr -d '"')
    if [[ -z "${apps_added[$app_name]}" ]]; then
        cat <<EOL >> "$nginx_conf"

        application $app_name {
            live on;
            on_publish http://localhost:81/rtmp/;
            hls on;
            hls_path /var/www/html/hls/$app_name;
            hls_cleanup off;
            hls_continuous off;
            hls_nested on;
            hls_fragment 1s;
            hls_playlist_length 3s;
        }
EOL
        apps_added[$app_name]=1
    fi
done

echo "  }" >> "$nginx_conf"
echo "}" >> "$nginx_conf"
