#!/bin/bash

ENV="$1"
SSH_KEY="$HOME/.ssh/id_ed25519_yacloud"
MASTER_NAME="k3s-master-$ENV"

if [[ "$ENV" != "stage" && "$ENV" != "prod" ]]; then
  echo "Usage: $0 [stage|prod]"
  exit 1
fi

MASTER_IP=$(yc compute instance get "$MASTER_NAME" --format json | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address')

if [[ -z "$MASTER_IP" ]]; then
  echo "Не удалось получить внешний IP мастера $MASTER_NAME"
  exit 1
fi

SSH_PRIV_KEY_CONTENT=$(cat "$SSH_KEY")
PUB_KEY=$(<"$SSH_KEY.pub")

ssh -t -i "$SSH_KEY" ubuntu@"$MASTER_IP" <<EOF
set -e

# # 0. Получаем Let's Encrypt сертификат ДО запуска k3s
# sudo apt-get install -y certbot

# sudo certbot certonly --standalone --non-interactive --agree-tos \
#   -m longlive@inbox.ru -d health-api

# # Проверяем, что сертификат получен
# if [ ! -f /etc/letsencrypt/live/health-api/fullchain.pem ]; then
#   echo "Сертификат не получен"
#   exit 1
# fi

# 1. Копирование ключей
mkdir -p ~/.ssh
grep -qxF "$PUB_KEY" ~/.ssh/authorized_keys || echo "$PUB_KEY" >> ~/.ssh/authorized_keys
cat > ~/.ssh/id_ed25519_yacloud <<EOKEY
$SSH_PRIV_KEY_CONTENT
EOKEY

chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys ~/.ssh/id_ed25519_yacloud

# 2. Установка yq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
yq --version

# 3. Получаем IP воркеров из hosts.yaml
WORKER1_IP=\$(yq '.all.children.workers.hosts."k3s-worker-1".ansible_host' ~/health-api/ansible/inventories/$ENV/hosts.yaml)
WORKER2_IP=\$(yq '.all.children.workers.hosts."k3s-worker-2".ansible_host' ~/health-api/ansible/inventories/$ENV/hosts.yaml)

# 4. Установка k3s на мастере
curl -sfL https://get.k3s.io -o /tmp/install-k3s.sh
chmod +x /tmp/install-k3s.sh
sudo /tmp/install-k3s.sh server \
  --disable traefik \
  --disable-cloud-controller \
  --disable-network-policy \
  --write-kubeconfig-mode 644

# 5. Проверка установки k3s
if ! [ -f /usr/local/bin/k3s ]; then
  echo "K3s НЕ установлен — остановка"
  exit 1
fi

# 6. Проверка k3s kubectl
if ! /usr/local/bin/k3s kubectl get nodes &>/dev/null; then
  echo "FATAL: k3s kubectl не работает!"
  exit 2
fi

# 7. Подготовка файлов для установки агента на воркерах (без интернета)
cp /usr/local/bin/k3s ~/k3s-agent

INTERNAL_IP=\$(hostname -I | awk '{print \$1}')
echo "K3S_URL=https://\${INTERNAL_IP}:6443" > ~/k3s-agent.env
echo "K3S_TOKEN=\$(sudo cat /var/lib/rancher/k3s/server/node-token | tr -d '\n')" >> ~/k3s-agent.env

# 8. Сохраняем в роль Ansible
mkdir -p ~/health-api/ansible/roles/k3s/files/
cp ~/k3s-agent ~/health-api/ansible/roles/k3s/files/k3s
cp ~/k3s-agent.env ~/health-api/ansible/roles/k3s/files/k3s-agent.env

# 9. Установка Ansible и запуск плейбука
sudo apt install -y ansible
cd ~/health-api/ansible
ansible-galaxy collection install -r requirements.yml
ANSIBLE_ROLES_PATH=roles \
ansible-playbook -i inventories/$ENV/hosts.yaml playbook.yaml \
--vault-password-file .vault_pass.txt \
--extra-vars "ENV=prod VERSION=v1.0.17"
EOF
