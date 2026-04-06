#!/bin/bash

# Usage: ./create-wp-vm.sh <VM_ID> <HOSTNAME> <IP> <SSH_USER>
# Example: ./create-wp-vm.sh 110 wp-vm-01 10.24.36.30 user1

VM_ID=$1
HOSTNAME=$2
IP=$3
SSH_USER=$4

# Shared configuration
GATEWAY="10.24.36.1"
GOLDEN_IMAGE="/var/lib/vz/template/golden/wp-golden.raw"
STORAGE="ceph-pool"
PASSWORD="changeme123"
MEMORY=1024
CORES=1

# Validate inputs
if [ -z "$VM_ID" ] || [ -z "$HOSTNAME" ] || [ -z "$IP" ] || [ -z "$SSH_USER" ]; then
  echo "Usage: $0 <VM_ID> <HOSTNAME> <IP> <SSH_USER>"
  exit 1
fi

echo "=== Creating VM $VM_ID ($HOSTNAME) ==="

# Create VM
qm create $VM_ID --name $HOSTNAME --memory $MEMORY --cores $CORES \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci --ostype l26 --serial0 socket

# Import golden image
echo "Importing golden image..."
qm disk import $VM_ID $GOLDEN_IMAGE $STORAGE
qm set $VM_ID --scsi0 ${STORAGE}:vm-${VM_ID}-disk-0
qm set $VM_ID --boot order=scsi0

# Mount disk and configure network + hostname
echo "Configuring network and hostname..."
rbd map ${STORAGE}/vm-${VM_ID}-disk-0
DEV=$(rbd showmapped | grep vm-${VM_ID}-disk-0 | awk '{print $NF}')
mount ${DEV}p1 /mnt/vm-disk

echo "$HOSTNAME" > /mnt/vm-disk/etc/hostname
cat > /mnt/vm-disk/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto ens18
iface ens18 inet static
  address ${IP}/24
  gateway ${GATEWAY}
  dns-nameservers 1.1.1.1
EOF

systemd-machine-id-setup --root=/mnt/vm-disk
umount /mnt/vm-disk
rbd unmap $DEV

# Start VM
qm start $VM_ID
echo "Waiting for VM to boot..."
sleep 20

# Install WordPress and dependencies
echo "=== Installing packages ==="
ssh -o StrictHostKeyChecking=no root@$IP bash -c "'
apt update && apt upgrade -y
apt install -y apache2 mariadb-server php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip wget curl openssh-server

systemctl start mariadb
systemctl enable mariadb

mysql -u root <<SQLEOF
CREATE DATABASE wordpress;
CREATE USER \"wpuser\"@\"localhost\" IDENTIFIED BY \"wppassword\";
GRANT ALL PRIVILEGES ON wordpress.* TO \"wpuser\"@\"localhost\";
FLUSH PRIVILEGES;
SQLEOF

cd /tmp
wget -q https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* /var/www/html/
chown -R www-data:www-data /var/www/html/
rm -f /var/www/html/index.html

cd /var/www/html
cp wp-config-sample.php wp-config.php
sed -i \"s/database_name_here/wordpress/\" wp-config.php
sed -i \"s/username_here/wpuser/\" wp-config.php
sed -i \"s/password_here/wppassword/\" wp-config.php

systemctl restart apache2
'"

echo "=== Creating SSH user ==="
ssh root@$IP bash -c "'
useradd -m -s /bin/bash $SSH_USER
mkdir -p /home/$SSH_USER/.ssh
ssh-keygen -t ed25519 -f /home/$SSH_USER/.ssh/id_ed25519 -N \"\"
cp /home/$SSH_USER/.ssh/id_ed25519.pub /home/$SSH_USER/.ssh/authorized_keys
chown -R $SSH_USER:$SSH_USER /home/$SSH_USER/.ssh
chmod 700 /home/$SSH_USER/.ssh
chmod 600 /home/$SSH_USER/.ssh/authorized_keys
'"

echo "=== Installing node_exporter ==="
ssh root@$IP bash -c "'
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz
tar -xzf node_exporter-1.8.1.linux-amd64.tar.gz
cp node_exporter-1.8.1.linux-amd64/node_exporter /usr/local/bin/
useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null
cat > /etc/systemd/system/node_exporter.service <<NEOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
NEOF
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter
'"

echo "=== Configuring firewall ==="
cat > /etc/pve/firewall/${VM_ID}.fw <<FWEOF
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT

[RULES]
IN ACCEPT -p tcp -dport 22 -log nolog
IN ACCEPT -p tcp -dport 80 -log nolog
IN ACCEPT -p tcp -dport 443 -log nolog
IN ACCEPT -p tcp -dport 9100 -source 10.24.36.20 -log nolog
FWEOF

echo "=== Enabling HA ==="
ha-manager add vm:$VM_ID --state started --max_restart 3 --max_relocate 3

echo "=== Registering with Prometheus ==="
pct exec 200 -- bash -c "
if ! grep -q '${IP}:9100' /etc/prometheus/prometheus.yml; then
  sed -i \"/job_name: 'wordpress-vms'/,/labels:/{/labels:/i\\        - '${IP}:9100'}\" /etc/prometheus/prometheus.yml
  systemctl restart prometheus
fi
"

echo "=== Done! ==="
echo "WordPress: http://${IP}"
echo "SSH: ssh -i <key> ${SSH_USER}@${IP}"
