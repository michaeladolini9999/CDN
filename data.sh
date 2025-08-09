#!/bin/bash

DATA_DIR="/home/ubuntu/CDN/data/log"
OLD_DIR="/home/ubuntu/CDN/data/old_log"
OUTPUT_FILE="/home/ubuntu/CDN/data/data.csv"

check_and_add_header() {
    if [ ! -f "$OUTPUT_FILE" ]; then
        FIRST_FILE=$(find "$DATA_DIR" -name "bw_*.csv" | sort | head -n 1)
        if [ -n "$FIRST_FILE" ]; then
            head -n 1 "$FIRST_FILE" > "$OUTPUT_FILE"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Recreated $OUTPUT_FILE with header from $FIRST_FILE"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - No CSV files found in $DATA_DIR. Waiting for new files..."
        fi
    fi
}

check_new_files() {
    csv_files=$(find "$DATA_DIR" -name "bw_*.csv" -printf "%T@ %p\n" | sort -n | awk '{print $2}')
    if [ -z "$csv_files" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - No new CSV files found. Waiting for new files..."
        return
    fi

    for file in $csv_files; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') - New file detected: $file"
        tail -n +2 "$file" >> "$OUTPUT_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Appended $file to $OUTPUT_FILE"
        sudo mv "$file" "$OLD_DIR/"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Moved $file to $OLD_DIR"
    done
}

delete_old_files() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Deleting old .ts files (older than 30 seconds)"
    sudo find /var/www/html/hls/*/*/*.ts -maxdepth 1 -type f ! -newermt "$(date -d '30 seconds ago' +'%Y-%m-%d %H:%M:%S')" -delete
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Deleting old .m3u8 files (older than 30 seconds)"
    sudo find /var/www/html/hls/*/*/*.m3u8 -maxdepth 1 -type f ! -newermt "$(date -d '30 seconds ago' +'%Y-%m-%d %H:%M:%S')" -delete
}

check_and_add_header
check_new_files
delete_old_files

config_file="/home/ubuntu/CDN/server.json"

jq -c '.apps[] | [.[0], .[2], .[3]]' $config_file | while read -r pair; do
    domain=$(echo "$pair" | jq -r '.[0]')
    app_name=$(echo "$pair" | jq -r '.[1]')
    stream_name=$(echo "$pair" | jq -r '.[2]')

    target_dir="/var/www/html/hls/$app_name/$stream_name"
    index_file="$target_dir/index.m3u8"
    if [ -f "$index_file" ]; then
        playlist_file="$target_dir/playlist.m3u8"
        sudo tee "$playlist_file" > /dev/null <<EOF
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1920x1080
https://$domain:9090/hls/$app_name/$stream_name/index.m3u8
EOF
        echo "[OK] Đã tạo $playlist_file"
    else
        echo "[SKIP] Không tìm thấy $index_file"
    fi

    edge_index_file="$target_dir/$stream_name-index.m3u8"
    if [ -f "$edge_index_file" ]; then
        edge_playlist_file="$target_dir/$stream_name-playlist.m3u8"
        sudo tee "$edge_playlist_file" > /dev/null <<EOF
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1920x1080
https://$domain:9090/hls/$app_name/$stream_name/$stream_name-index.m3u8
EOF
        echo "[OK] Đã tạo $edge_playlist_file"
    else
        echo "[SKIP] Không tìm thấy $edge_index_file"
        if [ -f "$index_file" ]; then
            edge_playlist_file="$target_dir/$stream_name-playlist.m3u8"
            sudo tee "$edge_playlist_file" > /dev/null <<EOF
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1920x1080
https://$domain:9090/hls/$app_name/$stream_name/index.m3u8
EOF
            echo "[OK] Đã tạo $edge_playlist_file"
        else
            echo "[SKIP] Không tìm thấy $index_file"
        fi
    fi
done
