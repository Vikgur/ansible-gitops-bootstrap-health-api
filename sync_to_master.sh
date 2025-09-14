#!/bin/bash

ENV="$1"

if [[ "$ENV" != "stage" && "$ENV" != "prod" ]]; then
  echo "Usage: $0 [stage|prod]"
  exit 1
fi

MASTER_NAME="k3s-master-$ENV"
SSH_KEY="~/.ssh/id_ed25519_yacloud"

MASTER_IP=$(yc compute instance get "$MASTER_NAME" --format json | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address')

if [[ -z "$MASTER_IP" ]]; then
  echo "Не удалось получить внешний IP мастера $MASTER_NAME"
  exit 1
fi

ssh -i "$SSH_KEY" ubuntu@"$MASTER_IP" "mkdir -p ~/health-api/{ansible,helm,bitnami_charts}"

rsync -av -e "ssh -i $SSH_KEY" ansible/ ubuntu@"$MASTER_IP":~/health-api/ansible/

rsync -av -e "ssh -i $SSH_KEY" \
  --exclude-from=helm/rsync-exclude.txt \
  helm/ ubuntu@"$MASTER_IP":~/health-api/helm/

rsync -av -e "ssh -i $SSH_KEY" \
  --include='bitnami/' \
  --include='bitnami/postgresql/***' \
  --exclude='*' \
  bitnami_charts/ ubuntu@"$MASTER_IP":~/health-api/bitnami_charts/

echo "ansible/, helm/, bitnami_charts/ скопированы на мастер $ENV ($MASTER_IP)"
