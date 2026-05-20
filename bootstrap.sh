#!/usr/bin/env bash
# bootstrap.sh — Cria ou sobe uma workbench.
# Sem argumentos: pergunta o nome e cria tudo do zero (ou sobe se já existir).
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}→${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

cd "$(dirname "$0")"

# --- 1. Pré-requisitos ------------------------------------------------------
info "Verificando pré-requisitos..."
command -v docker >/dev/null || error "Docker não encontrado. Instala o Docker Desktop."
docker info >/dev/null 2>&1 || error "Docker não está rodando. Abre o Docker Desktop."

# --- 2. Nome da workbench ---------------------------------------------------
echo ""
read -rp "Nome da workbench: " INSTANCE_NAME
[ -z "$INSTANCE_NAME" ] && error "Nome não pode ser vazio."

ENV_FILE="workbenches/${INSTANCE_NAME}/.env"

# --- 3. Workbench nova ou existente? ----------------------------------------
if [ -f "$ENV_FILE" ]; then
  info "Workbench '${INSTANCE_NAME}' já existe — subindo."
  SSH_PORT=$(grep '^SSH_PORT=' "$ENV_FILE" | cut -d= -f2 || true)
else
  info "Criando nova workbench '${INSTANCE_NAME}'..."

  # Detecta a primeira porta livre a partir de 2222
  SSH_PORT=2222
  while lsof -iTCP:"$SSH_PORT" -sTCP:LISTEN >/dev/null 2>&1; do
    SSH_PORT=$(( SSH_PORT + 1 ))
  done
  info "Porta SSH alocada: $SSH_PORT"

  # Gera chave SSH dedicada
  SSH_KEY="$HOME/.ssh/$INSTANCE_NAME"
  if [ ! -f "$SSH_KEY" ]; then
    info "Gerando chave SSH em $SSH_KEY..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "${INSTANCE_NAME}@$(hostname)"
  fi

  # Cria o .env da workbench
  mkdir -p "workbenches/${INSTANCE_NAME}"
  cat > "$ENV_FILE" <<EOF
INSTANCE_NAME=${INSTANCE_NAME}
SSH_PORT=${SSH_PORT}
AUTHORIZED_KEY=$(cat "$HOME/.ssh/${INSTANCE_NAME}.pub")
EOF
  info ".env criado em $ENV_FILE"

  # Adiciona bloco no ~/.ssh/config
  SSH_CONFIG="$HOME/.ssh/config"
  touch "$SSH_CONFIG" && chmod 600 "$SSH_CONFIG"
  if ! grep -q "^Host ${INSTANCE_NAME}$" "$SSH_CONFIG"; then
    info "Adicionando 'Host ${INSTANCE_NAME}' ao ssh config..."
    cat >> "$SSH_CONFIG" <<SSHEOF

Host ${INSTANCE_NAME}
  HostName 127.0.0.1
  Port ${SSH_PORT}
  User dev
  IdentityFile ~/.ssh/${INSTANCE_NAME}
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  ForwardAgent yes
SSHEOF
  fi
fi

# Atalho pro docker compose desta workbench
DC="docker compose --project-name ${INSTANCE_NAME} --env-file ${ENV_FILE}"

# --- 4. Build e up ----------------------------------------------------------
info "Buildando a imagem..."
$DC build

info "Subindo o container..."
$DC up -d

# --- 5. Aguardar SSH --------------------------------------------------------
info "Aguardando SSH ficar disponível..."
for i in {1..30}; do
  if ssh -o ConnectTimeout=2 -o BatchMode=yes "${INSTANCE_NAME}" 'echo ok' >/dev/null 2>&1; then
    break
  fi
  sleep 1
  [ $i -eq 30 ] && error "SSH não respondeu em 30s. Verifica 'docker compose logs'."
done

# --- 6. Aguardar Postgres ---------------------------------------------------
info "Aguardando Postgres ficar pronto..."
for i in {1..30}; do
  if ssh "${INSTANCE_NAME}" 'pg_isready -q' >/dev/null 2>&1; then
    break
  fi
  sleep 1
  [ $i -eq 30 ] && warn "Postgres não respondeu em 30s. Cheque: ssh ${INSTANCE_NAME} 'sudo supervisorctl status'"
done

# --- 7. Permissões dos scripts ----------------------------------------------
chmod +x scripts/*.sh

# --- 8. Mensagem final ------------------------------------------------------
echo -e "
${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}✓ Workbench '${INSTANCE_NAME}' pronta!${NC}

  • SSH      → 127.0.0.1:${SSH_PORT}
  • Postgres → localhost:5432 (dentro do container)
  • Redis    → localhost:6379 (dentro do container)

Conecta o Zed:  File → Open Remote Project → Add Server → ${INSTANCE_NAME}
Terminal:        ssh ${INSTANCE_NAME}

${GREEN}═══════════════════════════════════════════════════════════════${NC}"
