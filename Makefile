SHELL := /bin/bash

.PHONY: all help check-env lint add-ips sync deploy secrets-scan lint-security

# Требуем явный ENV (stage|prod)
check-env:
	@if [ -z "$(ENV)" ]; then \
		echo "ERROR: ENV is not set (use ENV=stage or ENV=prod)"; \
		exit 1; \
	fi
	@if [ "$(ENV)" != "stage" ] && [ "$(ENV)" != "prod" ]; then \
		echo "ERROR: ENV must be 'stage' or 'prod'"; \
		exit 1; \
	fi

# Полный цикл: линтеры → IP → синк → деплой
all: check-env lint add-ips sync deploy

# Подсказка
help:
	@echo "Targets:"
	@echo "  all            - Full pipeline (lint → add-ips → sync → deploy)"
	@echo "  lint           - Run pre-commit linters (ansible-lint, yamllint, shellcheck)"
	@echo "  add-ips        - Update ansible/inventories/$${ENV}/hosts.yaml"
	@echo "  sync           - Sync ansible/ to master node"
	@echo "  deploy         - Run ansible-playbook on master node"
	@echo "  secrets-scan   - Run gitleaks scan for secrets"
	@echo "  lint-security  - Linters + secrets scan"

# DevSecOps проверки (pre-commit: ansible-lint, yamllint, shellcheck)
lint:
	pre-commit run --all-files

# Обновление inventory IP для окружения
add-ips: check-env
	./add_ips_to_hosts.sh $(ENV)

# Синхронизация ansible/ и вспомогательных файлов на мастер
sync: check-env
	./sync_to_master.sh $(ENV)

# Запуск плейбука на мастере (полный деплой всего стека)
deploy: check-env
	./run_ansible_on_master.sh $(ENV)

# Одноразовый bootstrap Argo CD (только роль argocd)
bootstrap-argocd: check-env
	./run_ansible_on_master.sh $(ENV) --tags argocd

# Поиск утечек секретов
secrets-scan:
	gitleaks detect --source . --redact --config .gitleaks.toml

# Всё сразу: линтеры + поиск секретов
lint-security: lint secrets-scan
