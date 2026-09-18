#!/bin/bash
# ==============================================================================
# SCRIPT DE VARREDURA DE REDE LOCAL E TESTE DE PORTAS
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

PORTAS_PADRAO=(22 80 443 3389 8080 8443)

# 1. Detecta a sub-rede principal (filtra a interface principal conectada)
GATEWAY_IP=$(ip route show default 2>/dev/null | head -n1 | awk '{print $3}')
SUBREDE=$(echo "$GATEWAY_IP" | cut -d'.' -f1-3)

[ -n "$SUBREDE" ] || die "Não foi possível detectar a interface de rede ativa ou gateway padrão."

echo "=========================================="
echo " 📡 VARREDURA DE REDE LOCAL: ${SUBREDE}.0/24 "
echo " Gateway Detectado: $GATEWAY_IP"
echo "=========================================="
echo "Buscando dispositivos online (Ping Sweep)..."

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
TEMP_IPS="${TEMP_DIR}/ips_ativos.txt"

# 2. Pings rápidos em paralelo com gravação por arquivo individual para evitar conflito
for i in $(seq 1 254); do
    (
        ip="${SUBREDE}.${i}"
        if ping -c 1 -W 1 "$ip" &>/dev/null; then
            echo "$ip" > "${TEMP_DIR}/${i}.host"
        fi
    ) &
done
wait

# Consolida os resultados
cat "${TEMP_DIR}"/*.host 2>/dev/null | sort -V > "$TEMP_IPS"
TOTAL_HOSTS=$(wc -l < "$TEMP_IPS")

if [ "$TOTAL_HOSTS" -eq 0 ]; then
    log_warn "Nenhum host respondeu ao ping na sub-rede ${SUBREDE}.0/24."
    exit 0
fi

echo -e "\n✅ Dispositivos Encontrados ($TOTAL_HOSTS ativos):"
echo "------------------------------------------"

# 3. Exibe IP, Hostname (se disponível) e MAC Address da tabela ARP
while read -r ip; do
    MAC=$(ip neighbor show "$ip" 2>/dev/null | awk '{print $5}' | grep -E '([0-9a-fA-F]{2}:){5}' || echo "N/A / Localhost")
    HOSTNAME=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}')
    HOSTNAME="${HOSTNAME:-Desconhecido}"
    printf "  • IP: %-15s | MAC: %-17s | Host: %s\n" "$ip" "$MAC" "$HOSTNAME"
done < "$TEMP_IPS"

echo -e "\n------------------------------------------"
echo "🔍 Testando portas essenciais nos hosts (${PORTAS_PADRAO[*]})..."

while read -r ip; do
    PORTAS_ABERTAS=""
    for porta in "${PORTAS_PADRAO[@]}"; do
        if timeout 0.6 bash -c "</dev/tcp/$ip/$porta" &>/dev/null; then
            PORTAS_ABERTAS="${PORTAS_ABERTAS}[$porta] "
        fi
    done

    if [ -n "$PORTAS_ABERTAS" ]; then
        echo "  🟢 Host $ip: $PORTAS_ABERTAS"
    else
        echo "  ⚪ Host $ip: [Nenhuma das portas padrão aberta]"
    fi
done < "$TEMP_IPS"

echo -e "\n=========================================="
