#!/bin/bash

echo "=== Deploying 3 WordPress containers (Klant 1) ==="

./create-wp.sh 100 wp-01 10.24.36.10 user1
./create-wp.sh 101 wp-02 10.24.36.11 user2
./create-wp.sh 102 wp-03 10.24.36.12 user3

echo "=== All containers deployed ==="
echo "Verifying..."
for ip in 10.24.36.{10..12}; do
  echo -n "$ip: "
  curl -s -o /dev/null -w "%{http_code}" http://$ip
  echo ""
done
