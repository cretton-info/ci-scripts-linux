#!/bin/bash
# ==============================================================================
# UPDATE — atualiza o repositório (git pull) e reinstala os scripts
# Uso: ./update.sh (a partir do checkout git de ci-scripts-linux)
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/lib/common.sh"

cd "$SCRIPT_DIR" || die "Não foi possível entrar em $SCRIPT_DIR"

[ -d .git ] || die "Isto não parece ser um checkout git de ci-scripts-linux (sem .git em $SCRIPT_DIR). Rode a partir do repositório clonado, não de ~/scripts/."

has_cmd git || die "Comando 'git' não encontrado."

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    log_warn "Há alterações locais não commitadas em $SCRIPT_DIR — o git pull pode falhar ou criar conflito."
fi

log_info "Atualizando repositório (git pull)..."
if ! git pull; then
    die "git pull falhou — resolva manualmente (conflito, rede, credenciais, etc.) e rode de novo."
fi

log_info "Reinstalando scripts em ~/scripts/ (sudo ./install.sh)..."
INSTALL_EXIT=0
if [ "$EUID" -eq 0 ]; then
    bash "${SCRIPT_DIR}/install.sh" || INSTALL_EXIT=$?
else
    sudo bash "${SCRIPT_DIR}/install.sh" || INSTALL_EXIT=$?
fi

if [ "$INSTALL_EXIT" -eq 0 ]; then
    log_ok "Atualização concluída."
else
    die "git pull funcionou, mas install.sh falhou (código ${INSTALL_EXIT}) — o repositório está atualizado, mas ~/scripts/ pode estar com versões antigas. Rode 'sudo ./install.sh' manualmente."
fi
