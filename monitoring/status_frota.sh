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
  WEBHOOK_URL   Se definida, alerta (um por host, com cooldown próprio por
                host+motivo) quando um host fica OFFLINE ou em ALERTA —
                dá pra rodar via cron sem precisar olhar o terminal.
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
    # ConnectTimeout só cobre a fase de conexão/autenticação — se o host responde o
    # handshake mas o comando remoto trava depois (ex.: "df" pendurado num NFS fora
    # do ar, "docker ps" sem resposta), isso aqui sozinho NÃO protege os outros hosts
    # da fila. ServerAlive* detecta a conexão morta e o "timeout" externo é a rede de
    # segurança final, cobrindo até a decisão do ssh de desistir.
    JSON=$(timeout "$((SSH_TIMEOUT * 3))" ssh -o ConnectTimeout="$SSH_TIMEOUT" -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
        "$host" 'bash ~/scripts/health_check.sh --json 2>/dev/null' 2>/dev/null)

    # Chave de cooldown por host (sanitizada): mesmo host com dois alertas no
    # mesmo motivo não dobra a notificação, mas hosts diferentes nunca
    # compartilham cooldown entre si.
    HOST_CHAVE=$(echo "$host" | tr -cs '[:alnum:]' '_')

    if [ -z "$JSON" ] || ! echo "$JSON" | jq empty 2>/dev/null; then
        printf "%-22s %-8s %6s %7s %9s %9s\n" "$host" "OFFLINE" "-" "-" "-" "-"
        PROBLEMAS=$((PROBLEMAS + 1))
        alert_webhook "frota_offline_${HOST_CHAVE}" "Host '${host}' não respondeu via SSH (fora do ar, sem acesso, ou o health_check.sh travou/falhou no host remoto)."
        continue
    fi

    MEM=$(echo "$JSON" | jq -r '.memoria_uso_pct // "?"')
    DISCO_MAX=$(echo "$JSON" | jq -r '[.disco[].uso_pct] | if length > 0 then max else 0 end')
    SERVICOS=$(echo "$JSON" | jq -r '.servicos_falhando | length')
    INTERNET=$(echo "$JSON" | jq -r 'if .conectividade.internet then "sim" else "NAO" end')

    STATUS="OK"
    MOTIVOS_ALERTA=()
    if [ "$MEM" != "?" ] && [ "$MEM" -ge "$LIMIAR_MEM" ] 2>/dev/null; then
        STATUS="ALERTA"; MOTIVOS_ALERTA+=("memória em ${MEM}% (limiar ${LIMIAR_MEM}%)")
    fi
    if [ "$DISCO_MAX" -ge "$LIMIAR_DISCO" ] 2>/dev/null; then
        STATUS="ALERTA"; MOTIVOS_ALERTA+=("disco em ${DISCO_MAX}% (limiar ${LIMIAR_DISCO}%)")
    fi
    if [ "$SERVICOS" -gt 0 ] 2>/dev/null; then
        STATUS="ALERTA"; MOTIVOS_ALERTA+=("${SERVICOS} serviço(s) systemd falhando")
    fi
    if [ "$INTERNET" = "NAO" ]; then
        STATUS="ALERTA"; MOTIVOS_ALERTA+=("sem conectividade com a internet")
    fi

    if [ "$STATUS" = "ALERTA" ]; then
        PROBLEMAS=$((PROBLEMAS + 1))
        # "${array[*]}" com IFS custom só usa o 1º caractere como separador —
        # não dá pra juntar com ", " assim. printf + remover a sobra do fim funciona.
        DETALHE_ALERTA=$(printf '%s, ' "${MOTIVOS_ALERTA[@]}")
        DETALHE_ALERTA="${DETALHE_ALERTA%, }"
        alert_webhook "frota_alerta_${HOST_CHAVE}" "Host '${host}': ${DETALHE_ALERTA}."
    fi

    printf "%-22s %-8s %6s %7s %9s %9s\n" "$host" "$STATUS" "$MEM" "$DISCO_MAX" "$SERVICOS" "$INTERNET"
done

echo "--------------------------------------------------------------------"
if [ "$PROBLEMAS" -eq 0 ]; then
    log_ok "Todos os ${#HOSTS[@]} host(s) OK."
else
    log_warn "${PROBLEMAS} de ${#HOSTS[@]} host(s) com alerta ou offline."
fi

[ "$PROBLEMAS" -eq 0 ]
