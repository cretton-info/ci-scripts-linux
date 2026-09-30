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
WEBHOOK_URL="${WEBHOOK_URL:-}"
ALERTA_COOLDOWN_HORAS="${ALERTA_COOLDOWN_HORAS:-6}"

echo "=========================================================="
echo " 🔍 SAÚDE DO SISTEMA — $(hostname) — $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================================="

echo -e "\n💻 CPU:"
MODELO_CPU=$(grep -m1 'model name' /proc/cpuinfo | cut -d':' -f2 | xargs)
if [ -z "$MODELO_CPU" ] && has_cmd lscpu; then
    MODELO_CPU=$(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)
fi
echo "  Modelo: ${MODELO_CPU:-$(uname -m)}"

echo -e "\n⏱️  Uptime / Carga:"
uptime

echo -e "\n💾 Uso de Memória:"
free -h
MEM_USO_PCT=$(free | awk '/^Mem:/{printf "%.0f", ($3/$2)*100}')
if [ -n "$MEM_USO_PCT" ] && [ "$MEM_USO_PCT" -ge "$LIMIAR_MEM" ] 2>/dev/null; then
    log_warn "Uso de memória em ${MEM_USO_PCT}% (limiar: ${LIMIAR_MEM}%)"
    alert_webhook "memoria" "${MEM_USO_PCT}% em uso (limiar ${LIMIAR_MEM}%)"
fi

echo -e "\n📀 Uso de Disco (partições > ${LIMIAR_DISCO}% em destaque):"
df -hP --exclude-type=tmpfs --exclude-type=devtmpfs | tail -n +2 | while read -r linha; do
    USO=$(echo "$linha" | awk '{print $5}' | tr -d '%')
    PARTICAO=$(echo "$linha" | awk '{print $1}')
    MONTADO_EM=$(echo "$linha" | awk '{print $NF}')
    if [ "$USO" -ge "$LIMIAR_DISCO" ] 2>/dev/null; then
        echo "  🔴 $linha"
        alert_webhook "disco_${MONTADO_EM}" "${PARTICAO} em ${MONTADO_EM} com ${USO}% (limiar ${LIMIAR_DISCO}%)"
    else
        echo "     $linha"
    fi
done

echo -e "\n🧠 Top 5 processos por uso de CPU:"
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 6

echo -e "\n📊 Top 5 processos por uso de RAM:"
ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -n 6

echo -e "\n🌐 Conectividade de Rede:"
if ping -c 2 -W 2 1.1.1.1 &>/dev/null; then
    log_ok "Conexão com a internet (IP): OK"
else
    log_warn "Conexão com a internet (IP): FALHA"
fi
if ping -c 2 -W 2 google.com &>/dev/null; then
    log_ok "Resolução DNS: OK"
else
    log_warn "Resolução DNS: FALHA"
fi

echo -e "\n🛠️  Serviços systemd falhando:"
if has_cmd systemctl; then
    FALHAS=$(systemctl list-units --state=failed --no-legend 2>/dev/null)
    if [ -n "$FALHAS" ]; then
        echo "$FALHAS"
        alert_webhook "servicos_systemd" "$(echo "$FALHAS" | wc -l) serviço(s) em estado de falha"
    else
        log_ok "Nenhum serviço em estado de falha."
    fi
fi

if has_cmd docker; then
    echo -e "\n🐳 Contêineres Docker:"
    docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null || log_warn "Não foi possível consultar o Docker (permissão?)."
fi

echo -e "\n=========================================================="
