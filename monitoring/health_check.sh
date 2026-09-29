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

# Envia um alerta em JSON para WEBHOOK_URL quando definido, com um cooldown por
# motivo (evita mandar o mesmo alerta repetidamente enquanto o problema persiste).
enviar_alerta() {
    local motivo="$1" detalhe="$2"
    [ -n "$WEBHOOK_URL" ] || return 0
    if ! has_cmd curl; then
        log_warn "WEBHOOK_URL definido mas curl não encontrado — alerta não enviado."
        return 0
    fi

    local estado_dir chave arquivo_estado
    estado_dir="$(dirname "$LOG_FILE" 2>/dev/null)/alertas"
    mkdir -p "$estado_dir" 2>/dev/null || estado_dir="/tmp/ci-scripts-linux-alertas"
    mkdir -p "$estado_dir" 2>/dev/null || true
    chave=$(echo "$motivo" | tr -cs '[:alnum:]' '_')
    arquivo_estado="${estado_dir}/${chave}.last"

    if [ -f "$arquivo_estado" ]; then
        local ultimo_ts agora_ts
        ultimo_ts=$(cat "$arquivo_estado" 2>/dev/null || echo 0)
        agora_ts=$(date +%s)
        if [ $(( (agora_ts - ultimo_ts) / 3600 )) -lt "$ALERTA_COOLDOWN_HORAS" ]; then
            return 0
        fi
    fi

    local payload
    payload=$(printf '{"hostname":"%s","motivo":"%s","detalhe":"%s","data":"%s"}' \
        "$(hostname)" "$motivo" "$detalhe" "$(date '+%Y-%m-%d %H:%M:%S')")

    if curl -fsS -m 10 -X POST -H 'Content-Type: application/json' -d "$payload" "$WEBHOOK_URL" >/dev/null 2>&1; then
        date +%s > "$arquivo_estado" 2>/dev/null || true
        log_info "Alerta enviado via webhook: ${motivo} (${detalhe})"
    else
        log_warn "Falha ao enviar alerta via webhook para: ${motivo}"
    fi
}

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
    enviar_alerta "memoria" "${MEM_USO_PCT}% em uso (limiar ${LIMIAR_MEM}%)"
fi

echo -e "\n📀 Uso de Disco (partições > ${LIMIAR_DISCO}% em destaque):"
df -hP --exclude-type=tmpfs --exclude-type=devtmpfs | tail -n +2 | while read -r linha; do
    USO=$(echo "$linha" | awk '{print $5}' | tr -d '%')
    PARTICAO=$(echo "$linha" | awk '{print $1}')
    MONTADO_EM=$(echo "$linha" | awk '{print $NF}')
    if [ "$USO" -ge "$LIMIAR_DISCO" ] 2>/dev/null; then
        echo "  🔴 $linha"
        enviar_alerta "disco_${MONTADO_EM}" "${PARTICAO} em ${MONTADO_EM} com ${USO}% (limiar ${LIMIAR_DISCO}%)"
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
        enviar_alerta "servicos_systemd" "$(echo "$FALHAS" | wc -l) serviço(s) em estado de falha"
    else
        log_ok "Nenhum serviço em estado de falha."
    fi
fi

if has_cmd docker; then
    echo -e "\n🐳 Contêineres Docker:"
    docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null || log_warn "Não foi possível consultar o Docker (permissão?)."
fi

echo -e "\n=========================================================="
