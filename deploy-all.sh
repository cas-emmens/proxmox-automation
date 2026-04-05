#!/bin/bash

echo "=== Deploying 6 WordPress containers ==="

./create-wp.sh 100 wp-01 10.24.36.10 user1
./create-wp.sh 101 wp-02 10.24.36.11 user2
./create-wp.sh 102 wp-03 10.24.36.12 user3
./create-wp.sh 103 wp-04 10.24.36.13 user4
./create-wp.sh 104 wp-05 10.24.36.14 user5
./create-wp.sh 105 wp-06 10.24.36.15 user6

echo "=== All containers deployed ==="
echo "Verifying..."
for ip in 10.24.36.{10..15}; do
  echo -n "$ip: "
  curl -s -o /dev/null -w "%{http_code}" http://$ip
  echo ""
done
