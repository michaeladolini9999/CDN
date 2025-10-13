#!/bin/bash
set -e

SUDOERS_LINE="ubuntu ALL=(ALL) NOPASSWD:ALL"

add_sudoers_line() {
    if ! sudo grep -qF "$SUDOERS_LINE" /etc/sudoers; then
        echo "$SUDOERS_LINE" | sudo EDITOR='tee -a' visudo
    fi
}

if id "ubuntu" &>/dev/null; then
    sudo usermod -aG sudo ubuntu
    add_sudoers_line
    sudo usermod -aG adm ubuntu
else
    sudo adduser --disabled-password --gecos "" ubuntu
    echo "ubuntu:Ubuntu24.04LTS" | sudo chpasswd
    sudo usermod -aG sudo ubuntu
    add_sudoers_line
    sudo usermod -aG adm ubuntu
fi

sudo su -l ubuntu <<'EOF'
cd
git clone https://github.com/michaeladolini9999/CDN.git
cd ~/CDN
git checkout op2srs
chmod +x *.sh
/home/ubuntu/CDN/install.sh
EOF
