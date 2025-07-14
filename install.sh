sudo timedatectl set-timezone Asia/Ho_Chi_Minh

chmod a+x /home/ubuntu/CDN/*.sh

interface=$(ip -4 -o addr show up primary scope global | awk '{print $2}' | head -n 1)
if [ -z "$interface" ]; then
    echo "Can not detect Internet interface."
    exit 1
fi

mac_address=$(ip link show "$interface" | awk '/ether/ {print $2}' | sed 's/://g')

if [ -z "$mac_address" ]; then
    echo "Can not get MAC address at $interface."
    exit 1
fi

current_hostname=$(hostname)

if [ "$current_hostname" == "$mac_address" ]; then
    echo "Hostname has changed before."
else
    sudo hostnamectl set-hostname "$mac_address"
    sudo sed -i "s/127.0.1.1.*/127.0.1.1 $mac_address/" /etc/hosts
    echo "Hostname is changed to $mac_address (at: $interface)"
fi

wget -O - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
echo "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/openresty.list
sudo apt update -y
sudo apt install gunicorn jq bmon net-tools libnginx-mod-rtmp php-fpm php  mysql-server python3 python3-watchdog python3-mysql.connector libssl-dev python3-flask-sqlalchemy python3-flask-bcrypt python3-pandas python3-python-flask-jwt-extended openresty -y
sudo apt remove apache2 -y
bash mysql.sh

chmod a+x /home/ubuntu/CDN/ulimit.sh
sudo /home/ubuntu/CDN/ulimit.sh

sudo bash -c 'cat > /etc/systemd/system/update_server_startup.service <<EOF
[Unit]
Description=My Startup Script
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/home/ubuntu/CDN/update_server.sh
RemainAfterExit=true
User=ubuntu
WorkingDirectory=/home/ubuntu

[Install]
WantedBy=multi-user.target
EOF'

sudo systemctl enable update_server_startup.service
sudo systemctl disable apt-daily-upgrade.timer
sudo systemctl disable apt-daily.timer
mountpoint -q /tmp/nginx_cache || sudo mount -t tmpfs -o size=1G tmpfs /tmp/nginx_cache
mkdir -p /home/ubuntu/CDN/log
sudo mkdir -p /etc/nginx/conf.d
sudo mkdir /var/log/openresty
sudo mkdir -p /etc/openresty/conf.d
sudo reboot
