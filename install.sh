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

sudo apt update -y
sudo apt install gunicorn jq bmon net-tools libnginx-mod-rtmp php-fpm php  mysql-server python3 python3-watchdog python3-mysql.connector libssl-dev python3-flask-sqlalchemy python3-flask-bcrypt python3-pandas python3-python-flask-jwt-extended -y
sudo apt remove apache2 -y
bash mysql.sh

sudo bash -c 'cat > /etc/systemd/system/cms.service <<EOF
[Unit]
Description=Gunicorn instance to serve cms
After=network.target

[Service]
User=ubuntu
Group=www-data
WorkingDirectory=/home/ubuntu/CDN
ExecStart=/usr/bin/gunicorn -w 2 -b unix:/var/run/cms/cms.sock cms:app

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

sudo mkdir -p /var/run/cms
sudo chown ubuntu:ubuntu /var/run/cms
chmod 755 /var/run/cms
sudo systemctl daemon-reload
sudo systemctl enable cms.service
sudo systemctl start cms.service
sudo systemctl enable update_server_startup.service
sudo systemctl start update_server_startup.service
mkdir -p /home/ubuntu/CDN/log
bash
