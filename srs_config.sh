#!/bin/bash

chmod a+x /home/ubuntu/CDN/ffmpeg
# Đường dẫn file JSON và config
JSON_FILE="/home/ubuntu/CDN/server.json"
SRS_CONFIG="/home/ubuntu/CDN/srs_ingest.conf"
TEMP_CONFIG="/tmp/srs_ingest_temp.conf"

# Biến đếm ingest hợp lệ
valid_count=0

# Ghi phần đầu vào file tạm
cat > "$TEMP_CONFIG" <<EOF
listen              127.0.0.1:1936;
max_connections     50000;
daemon              off;
srs_log_tank file;
srs_log_file /dev/null;
srs_log_level     error;
ff_log_dir        /dev/null;

http_server {
    enabled     on;
    listen      8888;
    crossdomain on;
    
    https {
        enabled     on;
        listen      9999;    
        key         /home/ubuntu/CDN/ssl/wild.globalup.asia/privkey.pem;
        cert        /home/ubuntu/CDN/ssl/wild.globalup.asia/fullchain.pem;
    }
}

vhost __defaultVhost__ {
EOF

# Duyệt từng app trong JSON (dùng process substitution để tránh subshell)
while read -r app; do
    origin=$(echo "$app" | jq -r '.[1]')
    appname=$(echo "$app" | jq -r '.[2]')
    stream=$(echo "$app" | jq -r '.[3]')

    # Bỏ qua nếu thiếu thông tin
    if [[ -z "$origin" || "$origin" == "null" || -z "$appname" || "$appname" == "null" || -z "$stream" || "$stream" == "null" ]]; then
        continue
    fi

    # Ghi ingest vào file tạm
    cat >> "$TEMP_CONFIG" <<EOF
    ingest ${appname,,}/${stream,,} {
        enabled     on;
        input {
            type    stream;
            url     rtmp://$origin:1935/$appname/$stream;
        }
        ffmpeg       /home/ubuntu/CDN/ffmpeg;
        engine {
            enabled  off;
            output   rtmp://127.0.0.1:1936/$appname/$stream;
        }
    }

EOF

    # Tăng số lượng ingest hợp lệ
    ((valid_count++))
done < <(jq -c '.apps[]' "$JSON_FILE")

# Nếu không có ingest hợp lệ thì xóa config và dừng SRS
if [[ $valid_count -eq 0 ]]; then
    echo "❌ Không tìm thấy ingest nào hợp lệ (origin/app/stream rỗng). Dừng SRS."
    rm -rf $SRS_CONFIG
    sudo systemctl stop srs.service
    sudo systemctl disable srs.service
    exit 1
fi

# Ghi phần cuối của config
cat >> "$TEMP_CONFIG" <<EOF
    hls {
        enabled        on;
        hls_path       /var/www/html/hls;
        hls_fragment   2;
        hls_window     5;
        hls_on_error   continue;
        hls_m3u8_file  [app]/[stream]/[stream]-index.m3u8;
        hls_ts_file    [app]/[stream]/[stream]-[seq].ts;
        hls_cleanup off;
        hls_dispose 15;
        hls_wait_keyframe off;
    }
    
    http_remux {
        enabled on;
        mount   /flv/[app]/[stream].flv;
        hstrs   on;
    }

    tcp_nodelay     on;
    min_latency     on;
    
    play {
        gop_cache       off;
        queue_length    10;
        mw_latency      100;
    }
    
    publish {
        mr off;
    }
}
EOF

mv "$TEMP_CONFIG" "$SRS_CONFIG"
sudo systemctl enable srs.service
sudo systemctl restart srs.service
echo "✅ Đã tạo file cấu hình: $SRS_CONFIG với $valid_count ingest hợp lệ và restart srs"
