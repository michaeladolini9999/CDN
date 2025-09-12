sudo timedatectl set-timezone Asia/Ho_Chi_Minh

chmod a+x /home/ubuntu/CDN/*.sh
chmod a+x /home/ubuntu/CDN/ffmpeg

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

#telegram
source ./telegram.conf

send_telegram() {
  local MESSAGE="$1"
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d "parse_mode=HTML" \
    --data-urlencode text="${MESSAGE}" > /dev/null
}

PUBLIC_IP=$(curl -s https://api.ipify.org)
CURRENT_DATETIME=$(date +"%Y-%m-%d %H:%M:%S")

MESSAGE=$(printf "<b>%s INSTALLING SERVER:</b>\n%s - %s" \
  "$CURRENT_DATETIME" "$(hostname)" "$PUBLIC_IP")

send_telegram "$MESSAGE"

#cloudflare
/home/ubuntu/CDN/cloudflare.sh

wget -O - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
echo "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/openresty.list
sudo apt update -y
sudo apt install -y jq bmon net-tools libnginx-mod-rtmp php-fpm php  mysql-server python3 python3-watchdog python3-mysql.connector libssl-dev python3-flask-sqlalchemy python3-flask-bcrypt python3-pandas python3-python-flask-jwt-extended openresty build-essential unzip automake cmake pkg-config ffmpeg
sudo apt remove apache2 -y
bash mysql.sh

sudo /home/ubuntu/CDN/ulimit.sh

cd /home/ubuntu/CDN; git clone https://github.com/ossrs/srs.git
cd /home/ubuntu/CDN/srs; git checkout 6.0release
cd /home/ubuntu/CDN/srs/trunk
./configure
make -j$(nproc)

sudo bash -c 'cat > /etc/systemd/system/srs.service <<EOF
[Unit]
Description=SRS (Simple Realtime Server)
After=network.target

[Service]
WorkingDirectory=/home/ubuntu/CDN/srs/trunk
ExecStart=/home/ubuntu/CDN/srs/trunk/objs/srs -c /home/ubuntu/CDN/srs_ingest.conf
Restart=always
RestartSec=3
LimitNOFILE=100000

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF'

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
mkdir -p /home/ubuntu/CDN/log
sudo mkdir -p /etc/nginx/conf.d
sudo mkdir /var/log/openresty
sudo mkdir -p /etc/openresty/conf.d
sudo reboot
