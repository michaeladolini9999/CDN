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
}

check_and_add_header
check_new_files
delete_old_files

