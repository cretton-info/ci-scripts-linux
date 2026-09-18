#!/bin/bash
# ==============================================================================
# SCRIPT DE SAÚDE DO SISTEMA (HEALTH CHECK)
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

LIMIAR_DISCO="${LIMIAR_DISCO:-85}"
LIMIAR_MEM="${LIMIAR_MEM:-90}"

echo "=========================================================="
echo " 🔍 SAÚDE DO SISTEMA — $(hostname) — $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================================="

echo -e "\n⏱️  Uptime / Carga:"
uptime

echo -e "\n💾 Uso de Memória:"
free -h

echo -e "\n📀 Uso de Disco (partições > ${LIMIAR_DISCO}% em destaque):"
df -hP --exclude-type=tmpfs --exclude-type=devtmpfs | tail -n +2 | while read -r linha; do
    USO=$(echo "$linha" | awk '{print $5}' | tr -d '%')
    if [ "$USO" -ge "$LIMIAR_DISCO" ] 2>/dev/null; then
        echo "  🔴 $linha"
    else
        echo "     $linha"
    fi
done

echo -e "\n🧠 Top 5 processos por uso de CPU:"
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 6

echo -e "\n🛠️  Serviços systemd falhando:"
if has_cmd systemctl; then
    FALHAS=$(systemctl list-units --state=failed --no-legend 2>/dev/null)
    if [ -n "$FALHAS" ]; then
        echo "$FALHAS"
    else
        log_ok "Nenhum serviço em estado de falha."
    fi
fi

if has_cmd docker; then
    echo -e "\n🐳 Contêineres Docker:"
    docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null || log_warn "Não foi possível consultar o Docker (permissão?)."
fi

echo -e "\n=========================================================="
