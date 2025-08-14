#!/bin/bash

source ./cloudflare.conf

if [[ -n "$NAME" ]]; then
    RECORD_NAME="$NAME"
else
    RECORD_NAME=$(hostname)
fi

PUBLIC_IP=$(curl -s https://api.ipify.org)

if [[ -z "$RECORD_NAME" || -z "$PUBLIC_IP" ]]; then
    echo "[ERROR] Can not get RECORD_NAME or IP."
    exit 1
fi

echo "[INFO] Record Name: $RECORD_NAME"
echo "[INFO] Public IP: $PUBLIC_IP"

# Get list of A records from Cloudflare
DNS_LIST=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=A" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json")

# Check whether IP existed
if echo "$DNS_LIST" | grep -q "\"content\":\"${PUBLIC_IP}\""; then
    echo "[INFO] IP: ${PUBLIC_IP} existed. Do nothing."
    exit 0
fi

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

CREATE_RESULT=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$JSON_DATA")

if echo "$CREATE_RESULT" | grep -q '"success":\s*true'; then
    echo "[INFO] Create new record successfully: ${RECORD_NAME} -> ${PUBLIC_IP}"
else
    echo "[ERROR] Create new record fail: $CREATE_RESULT"
    exit 1
fi
