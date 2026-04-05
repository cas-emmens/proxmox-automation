#!/bin/bash

# Configuration
CT_ID=100
HOSTNAME="wp-01"
IP="10.24.36.10"
GATEWAY="10.24.36.1"
TEMPLATE="local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
STORAGE="ceph-pool"
PASSWORD="changeme123"
DISK_SIZE=30
MEMORY=1024
CORES=1
RATE_LIMIT=50
SSH_USER="user1"

echo "=== Creating container $CT_ID ($HOSTNAME) ==="

# Create the container
pct create $CT_ID $TEMPLATE \
  --hostname $HOSTNAME \
  --storage $STORAGE \
  --rootfs ${STORAGE}:${DISK_SIZE} \
  --cores $CORES \
  --memory $MEMORY \
  --net0 name=eth0,bridge=vmbr0,ip=${IP}/24,gw=${GATEWAY},rate=${RATE_LIMIT} \
  --password $PASSWORD \
  --unprivileged 1 \
  --start 1

echo "Waiting for container to boot..."
sleep 10

echo "=== Installing packages ==="
pct exec $CT_ID -- bash -c "
apt update && apt upgrade -y
apt install -y apache2 mariadb-server php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip wget openssh-server
"

echo "=== Setting up MariaDB and WordPress ==="
pct exec $CT_ID -- bash -c "
# Start MariaDB
systemctl start mariadb
systemctl enable mariadb

# Create database
mysql -u root <<SQLEOF
CREATE DATABASE wordpress;
CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'wppassword';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';
FLUSH PRIVILEGES;
SQLEOF

# Download and install WordPress
cd /tmp
wget -q https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* /var/www/html/
chown -R www-data:www-data /var/www/html/
rm -f /var/www/html/index.html

# Configure WordPress
cd /var/www/html
cp wp-config-sample.php wp-config.php
sed -i 's/database_name_here/wordpress/' wp-config.php
sed -i 's/username_here/wpuser/' wp-config.php
sed -i 's/password_here/wppassword/' wp-config.php

systemctl restart apache2
"

echo "=== Creating SSH user ==="
pct exec $CT_ID -- bash -c "
useradd -m -s /bin/bash $SSH_USER
mkdir -p /home/$SSH_USER/.ssh
ssh-keygen -t ed25519 -f /home/$SSH_USER/.ssh/id_ed25519 -N ''
cp /home/$SSH_USER/.ssh/id_ed25519.pub /home/$SSH_USER/.ssh/authorized_keys
chown -R $SSH_USER:$SSH_USER /home/$SSH_USER/.ssh
chmod 700 /home/$SSH_USER/.ssh
chmod 600 /home/$SSH_USER/.ssh/authorized_keys
"

echo "=== Configuring firewall ==="
cat > /etc/pve/firewall/${CT_ID}.fw <<FWEOF
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT

[RULES]
IN ACCEPT -p tcp -dport 22 -log nolog
IN ACCEPT -p tcp -dport 80 -log nolog
IN ACCEPT -p tcp -dport 443 -log nolog
FWEOF

echo "=== Done! ==="
echo "WordPress: http://${IP}"
echo "SSH: ssh -i <key> ${SSH_USER}@${IP}"
