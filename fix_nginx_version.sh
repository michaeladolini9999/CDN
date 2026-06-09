sudo apt install \
    nginx=1.24.0-2ubuntu7.9 \
    nginx-common=1.24.0-2ubuntu7.9

# Verify
dpkg -l | grep -E 'nginx '
sudo nginx -t
