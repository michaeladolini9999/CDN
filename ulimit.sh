#!/bin/bash

LIMIT=100000

# override nginx, openresty, srs...
OVERRIDE_DIR="/etc/systemd/system/nginx.service.d"
if [ ! -d "$OVERRIDE_DIR" ]; then
    sudo mkdir -p "$OVERRIDE_DIR"
fi
sudo cp /home/ubuntu/CDN/override.conf $OVERRIDE_DIR

OVERRIDE_DIR="/etc/systemd/system/openresty.service.d"
if [ ! -d "$OVERRIDE_DIR" ]; then
    sudo mkdir -p "$OVERRIDE_DIR"
fi
sudo cp /home/ubuntu/CDN/override.conf $OVERRIDE_DIR

# /etc/sysctl.conf
sudo cp /home/ubuntu/CDN/sysctl-livestream.conf /etc/sysctl.d

SYSCTL_CONF="/etc/sysctl.conf"
if grep -q "^fs.file-max" "$SYSCTL_CONF"; then
  sed -i "s/^fs.file-max.*/fs.file-max = $LIMIT/" "$SYSCTL_CONF"
fi
sysctl -p

# /etc/security/limits.conf
sudo cp /home/ubuntu/CDN/security-livestream.conf /etc/security/limits.d

# PAM limits
for file in "/etc/pam.d/common-session" "/etc/pam.d/common-session-noninteractive"; do
  if ! grep -q "^session[[:space:]]\+required[[:space:]]\+pam_limits.so" "$file"; then
    echo "session required pam_limits.so" >> "$file"
  fi
done

# systemd
for conf_file in "/etc/systemd/system.conf" "/etc/systemd/user.conf"; do
  if grep -q "^DefaultLimitNOFILE" "$conf_file"; then
    sed -i "s/^DefaultLimitNOFILE.*/DefaultLimitNOFILE=$LIMIT/" "$conf_file"
  else
    echo "DefaultLimitNOFILE=$LIMIT" >> "$conf_file"
  fi
done

# Apply changes
systemctl daemon-reexec
