#!/bin/bash

# Đường dẫn đến thư mục override của Nginx
OVERRIDE_DIR="/etc/systemd/system/nginx.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"
HEADER="### Editing /etc/systemd/system/nginx.service.d/override.conf"

# Nội dung cần ghi vào file override
read -r -d '' OVERRIDE_CONTENT << 'EOF'

[Service]
LimitNOFILE=100000

### End of drop-in snippet.
EOF

# Tạo thư mục nếu chưa tồn tại
if [ ! -d "$OVERRIDE_DIR" ]; then
    echo "Tạo thư mục $OVERRIDE_DIR..."
    sudo mkdir -p "$OVERRIDE_DIR"
fi

# Kiểm tra xem file override đã tồn tại chưa
if [ -f "$OVERRIDE_FILE" ]; then
    # Kiểm tra nếu file chứa dòng header chỉ định
    if grep -q "^$HEADER" "$OVERRIDE_FILE"; then
        echo "File override đã chứa header, sẽ ghi đè nội dung mới."
    else
        echo "File override tồn tại nhưng không chứa header, sẽ ghi đè toàn bộ nội dung."
    fi
else
    echo "File override chưa tồn tại, tạo file mới."
fi

# Ghi đè nội dung mới vào file override
echo "$OVERRIDE_CONTENT" | sudo tee "$OVERRIDE_FILE" > /dev/null

# Reload cấu hình systemd và restart Nginx để thay đổi có hiệu lực
echo "Reload cấu hình systemd..."
sudo systemctl daemon-reload

echo "Restart Nginx..."
sudo systemctl restart nginx

echo "Đã cập nhật override file cho Nginx tại $OVERRIDE_FILE"

