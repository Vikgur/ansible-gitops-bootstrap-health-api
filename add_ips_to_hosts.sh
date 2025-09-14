#!/bin/bash

ENV="$1"

if [[ "$ENV" != "stage" && "$ENV" != "prod" ]]; then
  echo "Usage: $0 [stage|prod]"
  exit 1
fi

get_ip() {
  yc compute instance get "$1" --format json | jq -r '.network_interfaces[0].primary_v4_address.address'
}

WORKER1_NAME="k3s-worker-1-$ENV"
WORKER2_NAME="k3s-worker-2-$ENV"

WORKER1_IP=$(get_ip "$WORKER1_NAME")
WORKER2_IP=$(get_ip "$WORKER2_NAME")

if [[ -z "$WORKER1_IP" || -z "$WORKER2_IP" ]]; then
  echo "Не удалось получить IP воркеров"
  exit 1
fi

mkdir -p "ansible/inventories/$ENV"

cat > "ansible/inventories/$ENV/hosts.yaml" <<EOF
$ENV:
  children:
    master:
      hosts:
        k3s-master:
          ansible_host: 127.0.0.1
          ansible_connection: local
    workers:
      hosts:
        k3s-worker-1:
          ansible_host: $WORKER1_IP
        k3s-worker-2:
          ansible_host: $WORKER2_IP
EOF

echo "Inventory сгенерирован: ansible/inventories/$ENV/hosts.yaml"
