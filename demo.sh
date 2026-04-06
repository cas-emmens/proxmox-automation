#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_success() {
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ $1 succeeded${NC}"
  else
    echo -e "${RED}✗ $1 failed${NC}"
    exit 1
  fi
}

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Proxmox Automation Demo${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Show current state
echo -e "${YELLOW}=== Current state ===${NC}"
pct list 2>/dev/null
qm list 2>/dev/null
echo ""

# Cleanup Klant 1
echo -e "${YELLOW}=== Cleaning up Klant 1 LXC containers ===${NC}"
for id in 100 101 102; do
  pct stop $id 2>/dev/null || true
  pct destroy $id 2>/dev/null || true
done
echo -e "${GREEN}✓ Klant 1 containers removed${NC}"
echo ""

# Cleanup Klant 2
echo -e "${YELLOW}=== Cleaning up Klant 2 VMs ===${NC}"
for id in 110 111 112; do
  ha-manager remove vm:$id 2>/dev/null || true
  sleep 2
  qm stop $id --skiplock 2>/dev/null || true
  sleep 2
  qm destroy $id --skiplock 2>/dev/null || true
done
echo -e "${GREEN}✓ Klant 2 VMs removed${NC}"
echo ""

# Verify clean state
echo -e "${YELLOW}=== Verifying clean state ===${NC}"
pct list
qm list
echo ""

# Ensure monitoring container is running
echo -e "${YELLOW}=== Ensuring monitoring server is running ===${NC}"
pct start 200 2>/dev/null || true
sleep 10
if curl -s http://10.24.36.20:9090 > /dev/null 2>&1; then
  echo -e "${GREEN}✓ Monitoring server is running${NC}"
else
  echo -e "${RED}✗ Monitoring server failed to start. Aborting.${NC}"
  exit 1
fi
echo ""

# Deploy Klant 1
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Deploying Klant 1 (LXC - Ansible)${NC}"
echo -e "${YELLOW}========================================${NC}"
cd /root/proxmox-automation/ansible
ansible-playbook klant1.yml
check_success "Klant 1 deployment"
echo ""

# Verify Klant 1 WordPress
echo -e "${YELLOW}=== Verifying Klant 1 WordPress ===${NC}"
KLANT1_OK=true
for ip in 10.24.36.10 10.24.36.11 10.24.36.12; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$ip)
  if [ "$STATUS" = "302" ] || [ "$STATUS" = "200" ]; then
    echo -e "${GREEN}✓ $ip: HTTP $STATUS${NC}"
  else
    echo -e "${RED}✗ $ip: HTTP $STATUS${NC}"
    KLANT1_OK=false
  fi
done
if [ "$KLANT1_OK" = false ]; then
  echo -e "${RED}Klant 1 verification failed. Aborting.${NC}"
  exit 1
fi
echo ""

# Verify Klant 1 SSH users
echo -e "${YELLOW}=== Verifying Klant 1 SSH users ===${NC}"
for i in 1 2 3; do
  CT_ID=$((99+i))
  IP="10.24.36.$((9+i))"
  pct exec $CT_ID -- cat /home/user${i}/.ssh/id_ed25519 > /tmp/test_key 2>/dev/null
  chmod 600 /tmp/test_key
  if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 -i /tmp/test_key user${i}@${IP} "echo ok" 2>/dev/null | grep -q ok; then
    echo -e "${GREEN}✓ user${i}@${IP}: SSH key login works${NC}"
  else
    echo -e "${RED}✗ user${i}@${IP}: SSH key login failed${NC}"
  fi
  rm -f /tmp/test_key
done
echo ""

# Verify Klant 1 monitoring
echo -e "${YELLOW}=== Verifying Klant 1 monitoring ===${NC}"
sleep 15
for ip in 10.24.36.10 10.24.36.11 10.24.36.12; do
  HEALTH=$(curl -s http://10.24.36.20:9090/api/v1/targets | grep -o "\"${ip}:9100\"[^}]*\"health\":\"[a-z]*\"" | grep -o '"health":"[a-z]*"')
  if echo "$HEALTH" | grep -q "up"; then
    echo -e "${GREEN}✓ $ip: monitored (up)${NC}"
  else
    echo -e "${YELLOW}⚠ $ip: monitoring pending${NC}"
  fi
done
echo ""

# Deploy Klant 2
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Deploying Klant 2 (VM + HA - Ansible)${NC}"
echo -e "${YELLOW}========================================${NC}"
ansible-playbook klant2.yml
check_success "Klant 2 deployment"
echo ""

# Verify Klant 2 WordPress
echo -e "${YELLOW}=== Verifying Klant 2 WordPress ===${NC}"
KLANT2_OK=true
for ip in 10.24.36.30 10.24.36.31 10.24.36.32; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$ip)
  if [ "$STATUS" = "302" ] || [ "$STATUS" = "200" ]; then
    echo -e "${GREEN}✓ $ip: HTTP $STATUS${NC}"
  else
    echo -e "${RED}✗ $ip: HTTP $STATUS${NC}"
    KLANT2_OK=false
  fi
done
if [ "$KLANT2_OK" = false ]; then
  echo -e "${RED}Klant 2 verification failed.${NC}"
  exit 1
fi
echo ""

# Verify Klant 2 HA
echo -e "${YELLOW}=== Verifying Klant 2 HA ===${NC}"
ha-manager status
echo ""

# Verify Klant 2 SSH users
echo -e "${YELLOW}=== Verifying Klant 2 SSH users ===${NC}"
for i in 1 2 3; do
  VM_ID=$((109+i))
  IP="10.24.36.$((29+i))"
  ssh -o StrictHostKeyChecking=no root@$IP "cat /home/user${i}/.ssh/id_ed25519" > /tmp/test_key 2>/dev/null
  chmod 600 /tmp/test_key
  if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 -i /tmp/test_key user${i}@${IP} "echo ok" 2>/dev/null | grep -q ok; then
    echo -e "${GREEN}✓ user${i}@${IP}: SSH key login works${NC}"
  else
    echo -e "${RED}✗ user${i}@${IP}: SSH key login failed${NC}"
  fi
  rm -f /tmp/test_key
done
echo ""

# Final monitoring check
echo -e "${YELLOW}=== Final monitoring status ===${NC}"
sleep 15
curl -s http://10.24.36.20:9090/api/v1/targets | grep -o '"health":"[a-z]*"' | sort | uniq -c
echo ""

# Final summary
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Final State${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "Containers (Klant 1):"
pct list
echo ""
echo "VMs (Klant 2):"
qm list
echo ""
echo "HA Status:"
ha-manager status
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Demo complete!${NC}"
echo -e "${GREEN}========================================${NC}"
