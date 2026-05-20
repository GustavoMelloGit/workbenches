#!/usr/bin/env bash
# reset.sh — Apaga completamente uma workbench.
# Uso: ./scripts/reset.sh <nome> [--backup] [--keep-volume] [--yes]
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}→${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
step()  { echo -e "${BLUE}▸${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

cd "$(dirname "$0")/.."

# --- Argumentos -------------------------------------------------------------
INSTANCE_NAME="${1:-}"
if [ -z "$INSTANCE_NAME" ]; then
  # Lista workbenches disponíveis
  echo ""
  echo "Workbenches disponíveis:"
  for dir in workbenches/*/; do
    [ -f "${dir}.env" ] && echo "  • $(basename "$dir")"
  done
  echo ""
  read -rp "Nome da workbench para resetar: " INSTANCE_NAME
  [ -z "$INSTANCE_NAME" ] && error "Nome não pode ser vazio."
fi

ENV_FILE="workbenches/${INSTANCE_NAME}/.env"
[ ! -f "$ENV_FILE" ] && error "Workbench '${INSTANCE_NAME}' não encontrada em $ENV_FILE"

SKIP_CONFIRM=false; KEEP_VOLUME=false; DO_BACKUP=false
for arg in "${@:2}"; do
  case "$arg" in
    --yes|-y)       SKIP_CONFIRM=true ;;
    --keep-volume)  KEEP_VOLUME=true ;;
    --backup)       DO_BACKUP=true ;;
    --help|-h)      sed -n '2,10p' "$0"; exit 0 ;;
    *) error "Flag desconhecida: $arg" ;;
  esac
done

SSH_PORT=$(grep '^SSH_PORT=' "$ENV_FILE" | cut -d= -f2 || true)
VOLUME_NAME="${INSTANCE_NAME}_dev-home"
DC="docker compose --project-name ${INSTANCE_NAME} --env-file ${ENV_FILE}"

command -v docker >/dev/null || error "Docker não encontrado."

echo ""
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${RED}  RESET — workbench '${INSTANCE_NAME}'${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Será apagado:"
echo "  • Container '${INSTANCE_NAME}'"
if [ "$KEEP_VOLUME" = false ]; then
  echo -e "  • ${RED}Volume ${VOLUME_NAME} (projetos, configs, BANCOS POSTGRES, Redis)${NC}"
else
  echo -e "  • ${YELLOW}Volume PRESERVADO${NC} (--keep-volume)"
fi
echo "  • Imagem do devenv"
echo "  • ~/.ssh/${INSTANCE_NAME} e ~/.ssh/${INSTANCE_NAME}.pub"
echo "  • Bloco 'Host ${INSTANCE_NAME}' do ~/.ssh/config"
echo "  • workbenches/${INSTANCE_NAME}/.env"
[ "$DO_BACKUP" = true ] && echo -e "  ${GREEN}+ Backup do volume será criado antes${NC}"
echo ""

if [ "$SKIP_CONFIRM" = false ]; then
  read -rp "Tem certeza? Digite 'reset' para confirmar: " CONFIRM
  [ "$CONFIRM" = "reset" ] || { echo "Abortado."; exit 0; }
fi

# Backup
if [ "$DO_BACKUP" = true ] && docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  BACKUP_FILE="${INSTANCE_NAME}-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  step "Backup em ./$BACKUP_FILE..."
  docker run --rm -v "${VOLUME_NAME}:/data" -v "$PWD":/backup \
    alpine tar czf "/backup/$BACKUP_FILE" -C /data . 2>/dev/null || warn "Backup falhou."
  [ -f "$BACKUP_FILE" ] && info "Backup salvo: $BACKUP_FILE"
fi

step "Derrubando container e removendo imagem..."
if [ "$KEEP_VOLUME" = true ]; then
  $DC down --rmi all --remove-orphans 2>/dev/null || true
else
  $DC down -v --rmi all --remove-orphans 2>/dev/null || true
fi

if [ "$KEEP_VOLUME" = false ] && docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  step "Removendo volume residual..."
  docker volume rm "$VOLUME_NAME" >/dev/null
fi

if [ -f "$HOME/.ssh/${INSTANCE_NAME}" ] || [ -f "$HOME/.ssh/${INSTANCE_NAME}.pub" ]; then
  step "Removendo chave SSH..."
  rm -f "$HOME/.ssh/${INSTANCE_NAME}" "$HOME/.ssh/${INSTANCE_NAME}.pub"
fi

SSH_CONFIG="$HOME/.ssh/config"
if [ -f "$SSH_CONFIG" ] && grep -q "^Host ${INSTANCE_NAME}$" "$SSH_CONFIG"; then
  step "Removendo bloco 'Host ${INSTANCE_NAME}' do ssh config..."
  cp "$SSH_CONFIG" "$SSH_CONFIG.bak-$(date +%s)"
  awk -v host="Host ${INSTANCE_NAME}" '
    $0 == host        { skip=1; next }
    skip && /^Host /  { skip=0 }
    skip && /^$/      { next }
    !skip             { print }
  ' "$SSH_CONFIG" > "$SSH_CONFIG.tmp" && mv "$SSH_CONFIG.tmp" "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
fi

if [ -f "$HOME/.ssh/known_hosts" ] && \
   ssh-keygen -F "[127.0.0.1]:${SSH_PORT}" >/dev/null 2>&1; then
  step "Limpando known_hosts..."
  ssh-keygen -R "[127.0.0.1]:${SSH_PORT}" >/dev/null 2>&1 || true
fi

step "Removendo workbenches/${INSTANCE_NAME}/..."
rm -rf "workbenches/${INSTANCE_NAME}"

echo ""
echo -e "${GREEN}✓ Workbench '${INSTANCE_NAME}' removida.${NC}"
echo "Para recriar: ./bootstrap.sh"
echo ""
