#!/bin/bash

echo "=== Deploying 3 WordPress VMs (Klant 2 - HA) ==="

./create-wp-vm.sh 110 wp-vm-01 10.24.36.30 user1
./create-wp-vm.sh 111 wp-vm-02 10.24.36.31 user2
./create-wp-vm.sh 112 wp-vm-03 10.24.36.32 user3

echo "=== All VMs deployed ==="
echo "Verifying..."
for ip in 10.24.36.30 10.24.36.31 10.24.36.32; do
  echo -n "$ip: "
  curl -s -o /dev/null -w "%{http_code}" http://$ip
  echo ""
done

echo ""
echo "HA Status:"
ha-manager status
