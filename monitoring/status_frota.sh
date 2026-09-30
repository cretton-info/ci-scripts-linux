#!/bin/bash
# ==============================================================================
# STATUS DA FROTA — roda health_check.sh --json via SSH em vários hosts e
# agrega tudo numa tabela só
# Consultoria de TI & Gestão de Infraestrutura
# ==============================================================================
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/common.sh"

HOSTS_CONF="${HOSTS_CONF:-${SCRIPT_DIR}/hosts.conf}"
LIMIAR_DISCO="${LIMIAR_DISCO:-85}"
LIMIAR_MEM="${LIMIAR_MEM:-90}"
SSH_TIMEOUT="${SSH_TIMEOUT:-8}"

exibir_ajuda() {
    cat <<EOF
Uso: $0 [-h|--help]

Roda "health_check.sh --json" via SSH em cada host listado em hosts.conf e
mostra um resumo numa tabela só. Não altera nada nos hosts remotos — só
leitura. Requer que o ci-scripts-linux já esteja instalado (~/scripts/) em
cada host remoto, e acesso SSH sem senha (chave configurada previamente).

Variáveis de ambiente:
  HOSTS_CONF    Caminho do arquivo de hosts (padrão: hosts.conf ao lado
                deste script). Veja hosts.conf.example pro formato.
  LIMIAR_DISCO  Percentual de disco pra marcar ALERTA (padrão: 85)
  LIMIAR_MEM    Percentual de memória pra marcar ALERTA (padrão: 90)
  SSH_TIMEOUT   Timeout de conexão por host em segundos (padrão: 8)
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    exibir_ajuda
    exit 0
fi

has_cmd jq || die "Este script precisa do 'jq' pra interpretar o JSON de cada host. Instale com: sudo apt-get install -y jq"
has_cmd ssh || die "Comando 'ssh' não encontrado."

[ -f "$HOSTS_CONF" ] || die "Arquivo de hosts não encontrado: $HOSTS_CONF — copie hosts.conf.example e edite com os seus hosts."

HOSTS=()
while IFS= read -r linha; do
    [[ -z "$linha" || "$linha" =~ ^[[:space:]]*# ]] && continue
    HOSTS+=("$linha")
done < "$HOSTS_CONF"

[ "${#HOSTS[@]}" -gt 0 ] || die "Nenhum host válido em $HOSTS_CONF (linhas em branco ou só com # são ignoradas)."

echo "=========================================================="
echo " 🚦 STATUS DA FROTA — $(date '+%Y-%m-%d %H:%M:%S') (${#HOSTS[@]} host(s))"
echo "=========================================================="
printf "%-22s %-8s %6s %7s %9s %9s\n" "HOST" "STATUS" "MEM%" "DISCO%" "SERVIÇOS" "INTERNET"
echo "--------------------------------------------------------------------"

PROBLEMAS=0
for host in "${HOSTS[@]}"; do
    JSON=$(ssh -o ConnectTimeout="$SSH_TIMEOUT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "$host" 'bash ~/scripts/health_check.sh --json 2>/dev/null' 2>/dev/null)

    if [ -z "$JSON" ] || ! echo "$JSON" | jq empty 2>/dev/null; then
        printf "%-22s %-8s %6s %7s %9s %9s\n" "$host" "OFFLINE" "-" "-" "-" "-"
        PROBLEMAS=$((PROBLEMAS + 1))
        continue
    fi

    MEM=$(echo "$JSON" | jq -r '.memoria_uso_pct // "?"')
    DISCO_MAX=$(echo "$JSON" | jq -r '[.disco[].uso_pct] | if length > 0 then max else 0 end')
    SERVICOS=$(echo "$JSON" | jq -r '.servicos_falhando | length')
    INTERNET=$(echo "$JSON" | jq -r 'if .conectividade.internet then "sim" else "NAO" end')

    STATUS="OK"
    [ "$MEM" != "?" ] && [ "$MEM" -ge "$LIMIAR_MEM" ] 2>/dev/null && STATUS="ALERTA"
    [ "$DISCO_MAX" -ge "$LIMIAR_DISCO" ] 2>/dev/null && STATUS="ALERTA"
    [ "$SERVICOS" -gt 0 ] 2>/dev/null && STATUS="ALERTA"
    [ "$INTERNET" = "NAO" ] && STATUS="ALERTA"

    [ "$STATUS" = "ALERTA" ] && PROBLEMAS=$((PROBLEMAS + 1))

    printf "%-22s %-8s %6s %7s %9s %9s\n" "$host" "$STATUS" "$MEM" "$DISCO_MAX" "$SERVICOS" "$INTERNET"
done

echo "--------------------------------------------------------------------"
if [ "$PROBLEMAS" -eq 0 ]; then
    log_ok "Todos os ${#HOSTS[@]} host(s) OK."
else
    log_warn "${PROBLEMAS} de ${#HOSTS[@]} host(s) com alerta ou offline."
fi

[ "$PROBLEMAS" -eq 0 ]
