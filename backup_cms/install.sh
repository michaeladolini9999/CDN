sudo bash -c 'cat > /etc/systemd/system/backup_cms.service <<EOF
[Unit]
Description=Gunicorn instance to serve backup_cms
After=network.target

[Service]
User=ubuntu
Group=www-data
WorkingDirectory=/home/ubuntu/CDN/backup_cms
ExecStart=/usr/bin/gunicorn -w 2 -b unix:/var/run/backup_cms/backup_cms.sock backup_cms:app

[Install]
WantedBy=multi-user.target
EOF'

sudo mkdir -p /var/run/backup_cms
sudo chown ubuntu:ubuntu /var/run/backup_cms
chmod 755 /var/run/backup_cms
sudo systemctl daemon-reload
sudo systemctl enable backup_cms.service
sudo systemctl start backup_cms.service

MYSQL_USER="root"         

sudo mysql -u "$MYSQL_USER" <<EOF
CREATE DATABASE IF NOT EXISTS backup_data;

USE backup_data;

CREATE TABLE IF NOT EXISTS data (
  id INT AUTO_INCREMENT PRIMARY KEY,
  client_id INT NOT NULL,
  time DATETIME NOT NULL,
  server VARCHAR(50) NOT NULL,
  app VARCHAR(50) NOT NULL,
  stream VARCHAR(50) NOT NULL,
  requests INT NOT NULL,
  unique_users INT NOT NULL,
  data_sent BIGINT NOT NULL,
  UNIQUE (time, server, app, stream)
);

CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  hashed_password VARCHAR(255) NOT NULL
);

CREATE USER IF NOT EXISTS 'admin'@'%' IDENTIFIED BY 'stream';
GRANT ALL PRIVILEGES ON backup_data.* TO 'admin'@'%';

ALTER USER 'admin'@'%' IDENTIFIED WITH mysql_native_password BY 'stream';

FLUSH PRIVILEGES;
EOF

bash /home/ubuntu/CDN/backup_cms/nginx.sh
