#!/bin/bash
set -euo pipefail

SERVER_JSON="server.json"

# Lấy IP public
PUBLIC_IP=$(curl -s https://api.ipify.org)
if [[ -z "$PUBLIC_IP" ]]; then
    echo "❌ Không lấy được IP public"
    exit 1
fi

echo "🌐 IP hiện tại: $PUBLIC_IP"

# Lấy danh sách subdomain từ apps[*][8] (cột cuối)
SUBDOMAINS=$(jq -r '.apps[][8]' "$SERVER_JSON" | grep -v '^$' | sort -u)

for RECORD_NAME in $SUBDOMAINS; do
    BASE_DOMAIN=$(echo "$RECORD_NAME" | awk -F. '{print $(NF-1)"."$NF}')

    # Lấy thông tin cloudflare từ config
    CF_CONFIG=$(jq -r --arg bd "$BASE_DOMAIN" '.config[$bd] // empty' "$SERVER_JSON")

    if [[ -z "$CF_CONFIG" ]]; then
        echo "⚠️  Bỏ qua $RECORD_NAME (không có thông tin Cloudflare cho $BASE_DOMAIN)"
        continue
    fi

    CLOUDFLARE_API_TOKEN=$(echo "$CF_CONFIG" | awk '{print $1}')
    CLOUDFLARE_ZONE_ID=$(echo "$CF_CONFIG" | awk '{print $2}')

    COMMENT="Created at $(date '+%Y-%m-%d %H:%M:%S')"

    JSON_DATA=$(cat <<EOF
{
  "type": "A",
  "name": "${RECORD_NAME}",
  "content": "${PUBLIC_IP}",
  "ttl": 60,
  "proxied": false,
  "comment": "${COMMENT}"
}
EOF
)

    echo "➡️  Cập nhật DNS $RECORD_NAME ($BASE_DOMAIN)..."

    CREATE_RESULT=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$JSON_DATA")

    SUCCESS=$(echo "$CREATE_RESULT" | jq -r '.success')

    if [[ "$SUCCESS" == "true" ]]; then
        echo "✅ Thành công: $RECORD_NAME"
    else
        echo "❌ Lỗi khi tạo $RECORD_NAME:"
        echo "$CREATE_RESULT"
    fi
done

