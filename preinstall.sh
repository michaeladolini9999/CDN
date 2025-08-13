#!/bin/bash
set -e

SUDOERS_LINE="ubuntu ALL=(ALL) NOPASSWD:ALL"

# Hàm thêm dòng vào sudoers nếu chưa có
add_sudoers_line() {
    if ! sudo grep -qF "$SUDOERS_LINE" /etc/sudoers; then
        echo "$SUDOERS_LINE" | sudo EDITOR='tee -a' visudo
        echo "[INFO] Đã thêm dòng vào sudoers."
    else
        echo "[INFO] Dòng sudoers đã tồn tại, bỏ qua."
    fi
}

# Kiểm tra user ubuntu
if id "ubuntu" &>/dev/null; then
    echo "[INFO] User 'ubuntu' đã tồn tại. Thêm quyền..."
    sudo usermod -aG sudo ubuntu
    add_sudoers_line
    sudo usermod -aG adm ubuntu
    newgrp adm
else
    echo "[INFO] User 'ubuntu' chưa tồn tại. Đang tạo mới..."
    sudo adduser --disabled-password --gecos "" ubuntu
    echo "ubuntu:Abcd@1234#" | sudo chpasswd
    sudo usermod -aG sudo ubuntu
    add_sudoers_line
    sudo usermod -aG adm ubuntu
    newgrp adm
fi


sudo su -l ubuntu <<'EOF'
cd
git clone https://github.com/michaeladolini9999/CDN.git
cd ~/CDN
git checkout devluasrs
EOF
