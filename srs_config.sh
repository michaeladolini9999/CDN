#!/bin/bash
# Đường dẫn file JSON
JSON_FILE="/home/ubuntu/CDN/server.json"
SRS_CONFIG="/home/ubuntu/CDN/srs_ingest.conf"

# Header config cố định
cat > "$SRS_CONFIG" <<EOF
listen              127.0.0.1:1936;
max_connections     1000;
daemon              off;

vhost __defaultVhost__ {
EOF

# Đọc từng dòng apps và tạo khối ingest tương ứng
jq -c '.apps[]' "$JSON_FILE" | while read -r app; do
    domain=$(echo "$app" | jq -r '.[0]')
    origin=$(echo "$app" | jq -r '.[1]')
    appname=$(echo "$app" | jq -r '.[2]')
    stream=$(echo "$app" | jq -r '.[3]')

    echo "    ingest ${appname,,}/${stream,,} {" >> "$SRS_CONFIG"
    echo "        enabled     on;" >> "$SRS_CONFIG"
    echo "        input {" >> "$SRS_CONFIG"
    echo "            type    stream;" >> "$SRS_CONFIG"
    echo "            url     rtmp://$origin:1935/$appname/$stream;" >> "$SRS_CONFIG"
    echo "        }" >> "$SRS_CONFIG"
    echo "        ffmpeg       /home/ubuntu/CDN/ffmpeg;" >> "$SRS_CONFIG"
    echo "        engine {" >> "$SRS_CONFIG"
    echo "            enabled  off;" >> "$SRS_CONFIG"
    echo "            output   rtmp://127.0.0.1:1936/$appname/$stream;" >> "$SRS_CONFIG"
    echo "        }" >> "$SRS_CONFIG"
    echo "    }" >> "$SRS_CONFIG"
    echo "" >> "$SRS_CONFIG"
done

# Footer HLS config cố định
cat >> "$SRS_CONFIG" <<EOF
    hls {
        enabled        on;
        hls_path       /var/www/html/hls;
        hls_fragment   2;
        hls_window     5;
        hls_on_error   continue;
        hls_m3u8_file  [app]/[stream]/[stream]-index.m3u8;
        hls_ts_file    [app]/[stream]/[stream]-[seq].ts;
    }
}
EOF
echo "✅ Đã tạo file cấu hình: $SRS_CONFIG"
