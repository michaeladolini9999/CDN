#!/bin/bash

HOSTNAME=$(hostname)
for line in \
"net.ipv6.conf.all.disable_ipv6 = 1" \
"net.ipv6.conf.default.disable_ipv6 = 1" \
"net.ipv6.conf.lo.disable_ipv6 = 1"
do
    grep -qF "$line" /etc/sysctl.conf || echo "$line" | sudo tee -a /etc/sysctl.conf
done
sudo sysctl -p
sudo ufw disable
current_ip=$(curl -s https://api.ipify.org)

update_time=$(date '+%Y-%m-%d %H:%M:%S')
update_time=$(echo "$update_time" | sed 's/ /%20/g')

manager_url="https://script.google.com/macros/s/AKfycbzAdixaKlAKfK_gowgMN4uxrRjcqKLRU34X9xNLJZFTyztwsrNel5ptaQq0bj6_vvA8vw/exec"
url="${manager_url}?hostname=${HOSTNAME}&ip=${current_ip}&update_time=${update_time}"
echo $url
response=$(curl -L "$url")

if [ -z "$response" ]; then
    echo "Server do not response."
    exit 1
fi

echo "$response" > /home/ubuntu/CDN/server.json

######################################################

config_file="/home/ubuntu/CDN/server.json"

get_config_value() {
    local key=$1
    grep -oP '"'"$key"'"\s*:\s*"\K[^"]+' "$config_file"
}

bot_token=$(get_config_value "bot_token")
chat_id=$(get_config_value "chat_id")

send_telegram_message() {
    local message=$1
    curl -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" -d chat_id="$chat_id" -d text="$message"
}

ip_file="/home/ubuntu/CDN/ip.txt"

if [ ! -f "$ip_file" ] || [ ! -s "$ip_file" ]; then
    echo "$current_ip" > "$ip_file"
    echo "File ip.txt has just been created: $current_ip"
else
    saved_ip=$(cat "$ip_file")
    if [ "$current_ip" != "$saved_ip" ]; then
        echo "$current_ip" > "$ip_file"
        send_telegram_message "$HOSTNAME: IP public has been changed from $saved_ip to $current_ip."
        echo "File ip.txt has just been updated: $current_ip"
    else
        echo "IP does not change."
    fi
fi

######################################################
old_config_file="/home/ubuntu/CDN/old_server.json"
sudo mkdir -p /var/www/html/hls
mountpoint -q /var/www/html/hls || sudo mount -t tmpfs -o size=2G,nodev,nosuid,noexec,nodiratime,uid=www-data,gid=www-data tmpfs /var/www/html/hls

sudo cp /home/ubuntu/CDN/hlsplayer.html /var/www/html

if [ ! -f "$old_config_file" ]; then
    mkdir -p /home/ubuntu/CDN/data/log
    mkdir -p /home/ubuntu/CDN/data/old_log
    sudo cp -r  /home/ubuntu/CDN/rtmp /var/www/html/
    sudo cp "$config_file" /var/www/html/rtmp/

    jq -c '.apps[] | [.[2], .[3]]' $config_file | while read -r pair; do
        app_name=$(echo "$pair" | jq -r '.[0]')
        stream_name=$(echo "$pair" | jq -r '.[1]')
        sudo mkdir -p "/var/www/html/hls/$app_name/$stream_name"
    done


    sudo chown -R www-data: /var/www/html
    bash /home/ubuntu/CDN/nginx.sh
    sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    sudo rm -f /etc/nginx/conf.d/*.conf
    sudo cp /home/ubuntu/CDN/nginx/conf.d/*.conf /etc/nginx/conf.d/
    sudo cp /home/ubuntu/CDN/nginx/nginx.conf /etc/nginx/nginx.conf
    sudo systemctl restart nginx.service
    cp "$config_file" "$old_config_file"

    session="CDN"

    if ! tmux has-session -t $session 2>/dev/null; then
        bash /home/ubuntu/CDN/run.sh
    else
        tmux send-keys -t $session:1 C-c 'python3 /home/ubuntu/CDN/monitor.py' Enter
    fi
    
else
    if cmp -s "$config_file" "$old_config_file"; then
        echo "server.json không thay đổi."

        session="CDN"

        if ! tmux has-session -t $session 2>/dev/null; then
            bash /home/ubuntu/CDN/run.sh
        fi
    else
        sudo cp "$config_file" /var/www/html/rtmp/

        jq -c '.apps[] | [.[2], .[3]]' $config_file | while read -r pair; do
            app_name=$(echo "$pair" | jq -r '.[0]')
            stream_name=$(echo "$pair" | jq -r '.[1]')
            sudo mkdir -p "/var/www/html/hls/$app_name/$stream_name"
        done

        sudo chown -R www-data: /var/www/html
        bash /home/ubuntu/CDN/nginx.sh
        sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
        sudo rm -f /etc/nginx/conf.d/*.conf
        sudo cp /home/ubuntu/CDN/nginx/conf.d/*.conf /etc/nginx/conf.d/
        sudo cp /home/ubuntu/CDN/nginx/nginx.conf /etc/nginx/nginx.conf
        sudo systemctl restart nginx.service
	cp "$config_file" "$old_config_file"

        session="CDN"

        if ! tmux has-session -t $session 2>/dev/null; then
            bash /home/ubuntu/CDN/run.sh
        else
            tmux send-keys -t $session:1 C-c 'python3 /home/ubuntu/CDN/monitor.py' Enter
        fi
    fi
fi

[ -f /home/ubuntu/.ssh/authorized_keys ] || (mkdir -p /home/ubuntu/.ssh && touch /home/ubuntu/.ssh/authorized_keys && chmod 600 /home/ubuntu/.ssh/authorized_keys && chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys)
key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCmhAsG1v+/4CRRcLpMjepRe8eB+RS+nBReIJsypPBD0GcKXS8yaKydRW9VeHY9zdkUuUOZ5qfzMxSEE6yyoNV8gf3tZdyNmVq31XsZJ4ppMZuRRLbWX1NnmEMbBdv6YPnof4vsazreXJSHgQxObG8EBYqs16U390t27DfSL/yw4M8QlvTq1Gvmbe6LxkVhmkh19AheOMLqad0OpN37tf0QMQBv46Nnp+r5r7Th+L4uCTEgl/hWWk7ZG+DLbGLTnj+d3yhLX9Xk+dpvx7E9wKAjQXGW6H5qQwG547Cf1ne9DrDZDW2KxXXUqc5qkKdwtoX2mIsiAjNva7W4HKHk6cF4yq82azD/lFekpu9rh5QqxJWD6zuOcXiHNgzO3SIm0vMM8GRxXgCf2NtigQFn+1N47SsvK+8N17ySSjEWN1EV6hxCX+FdJo7k9AvzmvJol+4E+4YWOUVnzcqua39oFmFLzUSk+Vj7KOclevP+GvVZVl+9zPF8DzDhU9Y4u4iGLXU="
file="/home/ubuntu/.ssh/authorized_keys"
grep -qxF "$key" "$file" || echo "$key" >> "$file"
if grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
    sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
else
    echo "PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config > /dev/null
fi
sudo systemctl restart ssh.service
(crontab -l 2>/dev/null | grep -q "/home/ubuntu/CDN/database.py") || (crontab -l 2>/dev/null; echo "*/5 * * * * python3 /home/ubuntu/CDN/database.py") | crontab -
mountpoint -q /tmp/nginx_cache || sudo mount -t tmpfs -o size=1G tmpfs /tmp/nginx_cache

