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

#echo "Restart Nginx..."
#sudo systemctl restart nginx

echo "Đã cập nhật override file cho Nginx tại $OVERRIDE_FILE"

# Đặt giá trị giới hạn mong muốn
LIMIT=65535

# Kiểm tra quyền root
if [ "$(id -u)" -ne 0 ]; then
  echo "Vui lòng chạy script với quyền root (sudo)."
  exit 1
fi

# 1. Cập nhật /etc/sysctl.conf
SYSCTL_CONF="/etc/sysctl.conf"
if grep -q "^fs.file-max" "$SYSCTL_CONF"; then
  sed -i "s/^fs.file-max.*/fs.file-max = $LIMIT/" "$SYSCTL_CONF"
else
  echo "fs.file-max = $LIMIT" >> "$SYSCTL_CONF"
fi
sysctl -p

# 2. Cập nhật /etc/security/limits.conf
LIMITS_CONF="/etc/security/limits.conf"
for user in "*" "root"; do
  for type in "soft" "hard"; do
    if ! grep -q "^$user[[:space:]]\+$type[[:space:]]\+nofile" "$LIMITS_CONF"; then
      echo "$user $type nofile $LIMIT" >> "$LIMITS_CONF"
    else
      sed -i "s/^$user[[:space:]]\+$type[[:space:]]\+nofile.*/$user $type nofile $LIMIT/" "$LIMITS_CONF"
    fi
  done
done

# 3. Đảm bảo PAM áp dụng giới hạn
for file in "/etc/pam.d/common-session" "/etc/pam.d/common-session-noninteractive"; do
  if ! grep -q "^session[[:space:]]\+required[[:space:]]\+pam_limits.so" "$file"; then
    echo "session required pam_limits.so" >> "$file"
  fi
done

# 4. Cập nhật cấu hình systemd
for conf_file in "/etc/systemd/system.conf" "/etc/systemd/user.conf"; do
  if grep -q "^DefaultLimitNOFILE" "$conf_file"; then
    sed -i "s/^DefaultLimitNOFILE.*/DefaultLimitNOFILE=$LIMIT/" "$conf_file"
  else
    echo "DefaultLimitNOFILE=$LIMIT" >> "$conf_file"
  fi
done

# 5. Áp dụng thay đổi
systemctl daemon-reexec

echo "Hoàn tất. Vui lòng đăng xuất và đăng nhập lại để áp dụng thay đổi."
