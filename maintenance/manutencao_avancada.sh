#!/bin/bash
# ==============================================================================
# SCRIPT DE MANUTENÇÃO, LIMPEZA & ATUALIZAÇÃO DO SISTEMA
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

require_root

AUTO_YES="${AUTO_YES:-0}"
for arg in "$@"; do
    [ "$arg" = "--yes" ] || [ "$arg" = "-y" ] && AUTO_YES=1
done

echo "=========================================================="
echo " 🧹 MANUTENÇÃO E LIMPEZA DO SISTEMA — $(hostname)"
echo "=========================================================="

DISCO_ANTES=$(df -h / | tail -n1 | awk '{print $4}')

log_info "1/5. Atualizando pacotes do sistema..."
apt-get update -y && apt-get upgrade -y

log_info "2/5. Removendo pacotes e dependências não utilizados..."
apt-get autoremove -y
apt-get autoclean -y

if has_cmd journalctl; then
    log_info "3/5. Limitando logs do journal a 200MB / 30 dias..."
    journalctl --vacuum-size=200M --vacuum-time=30d
else
    log_warn "3/5. journalctl não encontrado, pulando limpeza de logs."
fi

if has_cmd docker; then
    echo ""
    echo "🐳 O comando abaixo removerá imagens, redes e cache de build do Docker não usados"
    echo "   por nenhum contêiner em execução (não afeta contêineres nem volumes ativos):"
    docker system df 2>/dev/null || true
    if [ "$AUTO_YES" -eq 1 ] || confirm "4/5. Executar 'docker system prune' agora?"; then
        log_info "Limpando recursos Docker não utilizados..."
        docker system prune -f
    else
        log_warn "4/5. Limpeza do Docker pulada pelo usuário."
    fi
else
    log_warn "4/5. Docker não encontrado, pulando limpeza de contêineres."
fi

log_info "5/5. Limpando cache de pacotes .deb baixados..."
apt-get clean

DISCO_DEPOIS=$(df -h / | tail -n1 | awk '{print $4}')

echo -e "\n=========================================================="
log_ok "MANUTENÇÃO CONCLUÍDA!"
echo "=========================================================="
echo "📀 Espaço livre em / antes:  $DISCO_ANTES"
echo "📀 Espaço livre em / depois: $DISCO_DEPOIS"
echo "=========================================================="
